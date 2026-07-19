require "digest"
require "json"

module Aicoo
  class SnapshotCleanup
    SOURCE_TYPES = %w[gsc ga4].freeze
    INACTIVE_STATUSES = %w[archived ignored].freeze

    Result = Data.define(
      :mode,
      :checked_count,
      :archived_count,
      :active_count,
      :already_archived_count,
      :duplicate_group_count,
      :duplicate_snapshot_count,
      :before_duplicate_rate,
      :after_duplicate_rate,
      :failed_count,
      :archived_snapshot_ids,
      :source_type_summaries
    )

    Summary = Data.define(
      :source_type,
      :total_count,
      :active_count,
      :archived_count,
      :ignored_count,
      :duplicate_group_count,
      :duplicate_snapshot_count,
      :duplicate_rate
    )

    def self.call(...)
      new(...).call
    end

    def initialize(source_types: SOURCE_TYPES, apply: false, now: Time.current)
      @source_types = Array(source_types).map(&:to_s) & SOURCE_TYPES
      @apply = ActiveModel::Type::Boolean.new.cast(apply)
      @now = now
      @archived_count = 0
      @failed_count = 0
      @archived_snapshot_ids = []
    end

    def call
      summaries_before = source_types.index_with { |source_type| summary_for(source_type) }
      duplicate_groups.each_value do |snapshots|
        archive_duplicates!(snapshots)
      end
      summaries_after = source_types.index_with { |source_type| summary_for(source_type, projected: !apply) }

      Result.new(
        mode: apply ? "apply" : "dry-run",
        checked_count: snapshots.size,
        archived_count:,
        active_count: summaries_after.values.sum(&:active_count),
        already_archived_count: summaries_before.values.sum(&:archived_count) + summaries_before.values.sum(&:ignored_count),
        duplicate_group_count: summaries_before.values.sum(&:duplicate_group_count),
        duplicate_snapshot_count: summaries_before.values.sum(&:duplicate_snapshot_count),
        before_duplicate_rate: average_rate(summaries_before.values),
        after_duplicate_rate: average_rate(summaries_after.values),
        failed_count:,
        archived_snapshot_ids:,
        source_type_summaries: summaries_after.transform_values(&:to_h)
      )
    end

    private

    attr_reader :source_types, :apply, :now, :archived_count, :failed_count, :archived_snapshot_ids

    def snapshots
      @snapshots ||= AicooDataSnapshot
        .where(source_type: source_types)
        .order(:source_type, :captured_at, :created_at, :id)
        .to_a
    end

    def duplicate_groups
      @duplicate_groups ||= active_snapshots
        .group_by { |snapshot| group_key(snapshot) }
        .select { |_key, grouped| grouped.size > 1 }
    end

    def active_snapshots
      snapshots.reject { |snapshot| inactive_snapshot?(snapshot) }
    end

    def archive_duplicates!(snapshots)
      keeper = snapshots.max_by { |snapshot| [ snapshot.captured_at || Time.at(0), snapshot.created_at || Time.at(0), snapshot.id ] }
      fingerprint = fingerprint_for(keeper)
      snapshots.reject { |snapshot| snapshot.id == keeper.id }.each do |snapshot|
        unless apply
          @archived_snapshot_ids << snapshot.id
          @archived_count += 1
          next
        end

        archive_snapshot!(snapshot, keeper, fingerprint)
        @archived_snapshot_ids << snapshot.id
        @archived_count += 1
      rescue StandardError => e
        @failed_count += 1
        Rails.logger.warn("[Aicoo::SnapshotCleanup] archive failed snapshot_id=#{snapshot.id} #{e.class}: #{e.message}")
      end
      mark_keeper_active!(keeper, fingerprint) if apply
    end

    def archive_snapshot!(snapshot, keeper, fingerprint)
      payload = payload_for(snapshot).merge(
        "snapshot_status" => "archived",
        "snapshot_fingerprint" => fingerprint,
        "snapshot_fingerprint_version" => payload_for(snapshot)["snapshot_fingerprint_version"].presence || "metric_rows_v1",
        "archived_at" => now.iso8601,
        "archived_reason" => "duplicate_metric_snapshot",
        "active_snapshot_id" => keeper.id
      )
      snapshot.update!(payload:)
    end

    def mark_keeper_active!(snapshot, fingerprint)
      payload = payload_for(snapshot)
      return if payload["snapshot_status"] == "active" && payload["snapshot_fingerprint"].present?

      snapshot.update!(
        payload: payload.merge(
          "snapshot_status" => "active",
          "snapshot_fingerprint" => fingerprint,
          "snapshot_fingerprint_version" => payload["snapshot_fingerprint_version"].presence || "metric_rows_v1"
        )
      )
    end

    def summary_for(source_type, projected: false)
      rows = snapshots.select { |snapshot| snapshot.source_type == source_type }
      if projected
        active_rows = rows.reject { |snapshot| inactive_snapshot?(snapshot) || projected_archived_ids.include?(snapshot.id) }
        archived_rows = rows.select { |snapshot| archived_snapshot?(snapshot) || projected_archived_ids.include?(snapshot.id) }
      else
        active_rows = rows.reject { |snapshot| inactive_snapshot?(snapshot) }
        archived_rows = rows.select { |snapshot| archived_snapshot?(snapshot) }
      end
      ignored_rows = rows.select { |snapshot| ignored_snapshot?(snapshot) }
      duplicate_groups = active_rows.group_by { |snapshot| group_key(snapshot) }.values.select { |grouped| grouped.size > 1 }
      duplicate_snapshot_count = duplicate_groups.sum(&:size)

      Summary.new(
        source_type:,
        total_count: rows.size,
        active_count: active_rows.size,
        archived_count: archived_rows.size,
        ignored_count: ignored_rows.size,
        duplicate_group_count: duplicate_groups.size,
        duplicate_snapshot_count:,
        duplicate_rate: active_rows.any? ? ((duplicate_snapshot_count.to_d / active_rows.size) * 100).round(1).to_f : 0.0
      )
    end

    def projected_archived_ids
      @projected_archived_ids ||= duplicate_groups.values.flat_map do |grouped|
        keeper = grouped.max_by { |snapshot| [ snapshot.captured_at || Time.at(0), snapshot.created_at || Time.at(0), snapshot.id ] }
        grouped.reject { |snapshot| snapshot.id == keeper.id }.map(&:id)
      end
    end

    def group_key(snapshot)
      payload = payload_for(snapshot)
      [
        snapshot.source_type,
        snapshot.captured_at&.to_date&.iso8601,
        payload["business_id"].to_s,
        payload["analytics_site_id"].to_s,
        fingerprint_for(snapshot)
      ]
    end

    def fingerprint_for(snapshot)
      payload = payload_for(snapshot)
      payload["snapshot_fingerprint"].presence || Digest::SHA256.hexdigest(JSON.generate(
        "source_type" => payload["source_type"],
        "business_id" => payload["business_id"],
        "analytics_site_id" => payload["analytics_site_id"],
        "domain" => payload["domain"],
        "rows" => Array(payload["rows"]).map { |row| row.to_h.deep_stringify_keys.sort.to_h }.sort_by(&:to_json)
      ))
    end

    def payload_for(snapshot)
      snapshot.payload.to_h.deep_stringify_keys
    end

    def inactive_snapshot?(snapshot)
      payload_for(snapshot)["snapshot_status"].to_s.in?(INACTIVE_STATUSES)
    end

    def archived_snapshot?(snapshot)
      payload_for(snapshot)["snapshot_status"].to_s == "archived"
    end

    def ignored_snapshot?(snapshot)
      payload_for(snapshot)["snapshot_status"].to_s == "ignored"
    end

    def average_rate(summaries)
      active = summaries.sum(&:active_count)
      duplicates = summaries.sum(&:duplicate_snapshot_count)
      active.positive? ? ((duplicates.to_d / active) * 100).round(1).to_f : 0.0
    end
  end
end
