module Aicoo
  class ArticleOpportunityTodayConnector
    MODEL_NAME = TodayActionBoard::ARTICLE_OPPORTUNITY_MODEL_NAME
    ACTIVE_STATUSES = %w[idea proposal planning pending valuation_review_required approved].freeze

    Result = Data.define(
      :mode,
      :business,
      :latest_snapshot_at,
      :analyzer_result_count,
      :analyzer_action_candidate_count,
      :today_eligible_count,
      :duplicate_suppressed_count,
      :archived_count,
      :status_excluded_count,
      :fallback_used,
      :activated_count,
      :top10
    )

    Row = Data.define(
      :candidate,
      :candidate_id,
      :article_id,
      :article_path,
      :improvement_type,
      :improvement_type_label,
      :expected_improvement_score,
      :search_demand_score,
      :improvement_potential_score,
      :success_probability,
      :estimated_work_hours,
      :status,
      :generation_source,
      :today_exclusion_reason
    )

    def initialize(business:, apply: false, limit: nil)
      @business = business
      @apply = ActiveModel::Type::Boolean.new.cast(apply)
      @limit = limit&.to_i
      @activated_count = 0
    end

    def call
      activate_latest_archived_candidates! if apply
      rows = all_rows
      eligible = eligible_rows(rows)
      deduped = dedupe_rows(eligible)
      log_empty_today_reason!(rows, eligible, deduped)

      Result.new(
        mode: apply ? "apply" : "dry-run",
        business:,
        latest_snapshot_at: latest_snapshot_at,
        analyzer_result_count: analyzer_result.article_results.size,
        analyzer_action_candidate_count: analyzer_result.action_candidate_count,
        today_eligible_count: deduped.size,
        duplicate_suppressed_count: [ eligible.size - deduped.size, 0 ].max,
        archived_count: rows.count { |row| row.status == "archived" },
        status_excluded_count: rows.count { |row| !row.status.in?(ACTIVE_STATUSES) && row.status != "archived" },
        fallback_used: deduped.empty?,
        activated_count:,
        top10: deduped.sort_by { |row| row_sort_key(row) }.first(10)
      )
    end

    private

    attr_reader :business, :apply, :limit, :activated_count

    def activate_latest_archived_candidates!
      latest_rows_by_key(archived_rows).each_value do |row|
        candidate = row.candidate
        metadata = candidate.metadata.to_h.merge(
          "today_connected" => true,
          "today_activation_reason" => "article_opportunity_latest_snapshot",
          "today_activated_at" => Time.current.iso8601
        )
        candidate.update_columns(status: "proposal", metadata:, updated_at: Time.current)
        @activated_count += 1
      end
    end

    def all_rows
      @all_rows ||= candidate_scope.map { |candidate| build_row(candidate) }
    end

    def archived_rows
      candidate_scope.where(status: "archived").select { |candidate| production_candidate?(candidate) }.map { |candidate| build_row(candidate) }
    end

    def eligible_rows(rows)
      rows.select { |row| row.status.in?(ACTIVE_STATUSES) }
    end

    def dedupe_rows(rows)
      latest_rows_by_key(rows).values
    end

    def log_empty_today_reason!(rows, eligible, deduped)
      return if deduped.present?

      reason = if latest_snapshot_at.blank?
        "snapshot_missing"
      elsif analyzer_result.article_results.empty?
        "analyzer_result_empty"
      elsif rows.empty?
        "no_article_opportunity_candidate"
      elsif rows.all? { |row| row.status == "archived" }
        "all_candidates_archived"
      elsif eligible.empty?
        "status_not_eligible"
      else
        "duplicate_suppressed"
      end

      Rails.logger.info(
        "[Aicoo::ArticleOpportunityTodayConnector] no_today_eligible_candidate " \
          "business_id=#{business.id} reason=#{reason} latest_snapshot_at=#{latest_snapshot_at || '-'} " \
          "candidate_count=#{rows.size} eligible_count=#{eligible.size}"
      )
    end

    def latest_rows_by_key(rows)
      rows.group_by { |row| dedupe_key(row) }
          .transform_values { |group| group.max_by { |row| row_preference_key(row) } }
    end

    def candidate_scope
      scope = business.action_candidates.where("metadata ->> 'value_model_name' = ?", MODEL_NAME)
      scope = scope.limit(limit) if limit.to_i.positive?
      scope
    end

    def analyzer_result
      @analyzer_result ||= ArticleOpportunityAnalyzer.from_snapshots(business:, apply: false, limit:)
    end

    def latest_snapshot_at
      AicooDataSnapshot
        .where(source_type: "article_analytics")
        .where("payload ->> 'business_id' = ?", business.id.to_s)
        .where("COALESCE(payload ->> 'snapshot_status', 'active') NOT IN (?)", %w[archived ignored])
        .maximum(:captured_at)
    end

    def build_row(candidate)
      metadata = candidate.metadata.to_h
      Row.new(
        candidate:,
        candidate_id: candidate.id,
        article_id: metadata["article_id"],
        article_path: metadata["article_path"],
        improvement_type: metadata["opportunity_type"],
        improvement_type_label: improvement_type_label(metadata["opportunity_type"], metadata["opportunity_label"]),
        expected_improvement_score: decimal(metadata["expected_improvement_score"]),
        search_demand_score: decimal(metadata["search_demand_score"]),
        improvement_potential_score: decimal(metadata["improvement_potential_score"]),
        success_probability: decimal(metadata["success_probability"]),
        estimated_work_hours: decimal(metadata["estimated_work_hours"]),
        status: candidate.status,
        generation_source: candidate.generation_source,
        today_exclusion_reason: metadata["today_exclusion_reason"]
      )
    end

    def production_candidate?(candidate)
      metadata = candidate.metadata.to_h
      metadata["production_candidate"] == true &&
        metadata["daily_run_step"].to_s == ArticleOpportunityDailyRun::STEP_NAME &&
        metadata["experimental_only"] != true
    end

    def dedupe_key(row)
      [ business.id, row.article_id.presence || row.article_path, row.improvement_type ].join("::")
    end

    def row_preference_key(row)
      [
        snapshot_timestamp(row.candidate),
        row.candidate.created_at.to_i,
        row.candidate.id.to_i
      ]
    end

    def row_sort_key(row)
      [
        -row.expected_improvement_score,
        -row.search_demand_score,
        -row.improvement_potential_score,
        -row.success_probability,
        row.estimated_work_hours,
        -row.candidate.created_at.to_i
      ]
    end

    def snapshot_timestamp(candidate)
      snapshot_id = candidate.metadata.to_h["snapshot_id"]
      return 0 if snapshot_id.blank?

      AicooDataSnapshot.where(id: snapshot_id).pick(:captured_at)&.to_i || 0
    end

    def improvement_type_label(type, fallback)
      fallback.presence || {
        "ctr_improvement" => "CTR改善",
        "rank_improvement" => "順位改善",
        "internal_link_addition" => "内部リンク追加",
        "content_update" => "本文更新",
        "shop_addition" => "店舗追加",
        "verified_shop_addition" => "確認済店舗追加",
        "cta_improvement" => "送客CTA改善",
        "monitoring" => "継続観測"
      }.fetch(type.to_s, type.to_s.presence || "記事改善")
    end

    def decimal(value)
      value.to_s.delete(",").to_d
    end
  end
end
