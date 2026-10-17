module Aicoo
  class ShopDataGrowthProgressUpdater
    SOURCE_APPS = %w[suelog sue-log 吸えログ].freeze

    Result = Data.define(:matched_count, :updated_count, :completed_count)

    class << self
      def call(activity_log:)
        return empty_result unless relevant_activity?(activity_log)

        new(activity_log.business).call
      end

      def sync_business!(business)
        new(business).call
      end

      private

      def relevant_activity?(activity_log)
        activity_log.activity_type == "shop_created" &&
          activity_log.resource_type == "Shop" &&
          activity_log.source_app.to_s.in?(SOURCE_APPS)
      end

      def empty_result
        Result.new(matched_count: 0, updated_count: 0, completed_count: 0)
      end
    end

    def initialize(business)
      @business = business
    end

    def call
      candidates = candidate_scope.to_a
      updated_count = 0
      completed_count = 0

      candidates.each do |candidate|
        completed = sync_candidate!(candidate)
        updated_count += 1
        completed_count += 1 if completed
      rescue StandardError => e
        Rails.logger.warn(
          "[ShopDataGrowthProgress] sync failed candidate_id=#{candidate.id} " \
          "business_id=#{business.id} error=#{e.class}: #{e.message}"
        )
      end

      Result.new(matched_count: candidates.size, updated_count:, completed_count:)
    end

    private

    attr_reader :business

    def candidate_scope
      business.action_candidates
        .active_for_ranking
        .where("metadata ->> 'metric_rule' = ?", ShopDataGrowthPlan::METRIC_RULE)
    end

    def sync_candidate!(candidate)
      completed_now = false

      candidate.with_lock do
        candidate.reload
        next false if candidate.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)

        metadata = candidate.metadata.to_h.deep_stringify_keys
        progress = metadata.fetch("shop_data_growth_progress", {}).to_h
        initial_count = progress["initial_count"] || metadata["initial_count"] ||
          metadata.dig("evidence", "current_value") || metadata["current_value"] || 0
        started_at = progress_started_at(progress, candidate)
        target_count = progress["target_count"] || metadata["target_amount"] ||
          metadata.dig("evidence", "target_amount")
        plan = ShopDataGrowthPlan.new(
          business_name: business.name,
          current_count: initial_count,
          target_count:,
          completed_count: completed_activity_count(started_at)
        )
        completed_at = progress["completed_at"]
        completed_at ||= Time.current.iso8601 if plan.completed?
        progress_metadata = {
          "initial_count" => plan.initial_count,
          "target_count" => plan.add_count,
          "completed_count" => plan.completed_count,
          "remaining_count" => plan.remaining_count,
          "started_at" => started_at.iso8601,
          "last_synced_at" => Time.current.iso8601,
          "completed_at" => completed_at
        }.compact
        merged_metadata = metadata.merge(plan.metadata).merge(
          "metric_rule" => ShopDataGrowthPlan::METRIC_RULE,
          "shop_data_growth_progress" => progress_metadata
        )
        merged_metadata["evidence"] = metadata.fetch("evidence", {}).to_h.merge(plan.evidence)

        candidate.update_columns(metadata: merged_metadata, updated_at: Time.current)
        next false unless plan.completed?

        candidate.reload.mark_executed!(
          executed_by: "shop_activity",
          registered_count: plan.completed_count,
          completion_source: "shop_data_growth_progress",
          result_summary: "吸えログの店舗登録Activityが#{plan.completed_count}件に到達したため、自動完了しました。"
        )
        completed_now = true
      end

      completed_now
    end

    def progress_started_at(progress, candidate)
      value = progress["started_at"].presence
      return candidate.created_at unless value

      Time.zone.parse(value.to_s) || candidate.created_at
    rescue ArgumentError, TypeError
      candidate.created_at
    end

    def completed_activity_count(started_at)
      business.business_activity_logs
        .where(source_app: SOURCE_APPS, activity_type: "shop_created", resource_type: "Shop")
        .where(occurred_at: started_at..Time.current)
        .distinct
        .count(:resource_id)
    end
  end
end
