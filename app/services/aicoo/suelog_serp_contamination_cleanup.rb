module Aicoo
  class SuelogSerpContaminationCleanup
    DEFAULT_URL = "it-trend.jp/log_management/article/84-0008".freeze
    GENERATION_SOURCES = %w[serp serp_based integrated_decision].freeze
    CONTAMINATION_PATTERNS = [
      /it-trend\.jp/i,
      /log_management/i,
      /ログ管理/,
      /SERP差分/,
      /吸えログ\s*比較/,
      /外部比較サイトURL/,
      /新規事業探索由来/,
      %r{https?://[^"\s]*it-trend\.jp}i
    ].freeze

    Result = Data.define(
      :business,
      :trace,
      :archived_action_candidate_ids,
      :canceled_auto_revision_task_ids,
      :cancelled_action_execution_ids,
      :deduplicated_action_candidate_ids,
      :regenerated_count
    ) do
      def to_h
        {
          business_id: business&.id,
          business_name: business&.name,
          trace: trace&.to_h,
          archived_action_candidate_ids:,
          canceled_auto_revision_task_ids:,
          cancelled_action_execution_ids:,
          deduplicated_action_candidate_ids:,
          regenerated_count:
        }
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(url: DEFAULT_URL, regenerate: true)
      @url = url.to_s
      @regenerate = ActiveModel::Type::Boolean.new.cast(regenerate)
      @archived_action_candidate_ids = []
      @canceled_auto_revision_task_ids = []
      @cancelled_action_execution_ids = []
      @deduplicated_action_candidate_ids = []
    end

    def call
      raise ActiveRecord::RecordNotFound, "吸えログBusinessが見つかりません" unless business

      trace = Aicoo::UrlContaminationTracer.call(url:, fix: true)
      collect_trace_repairs!(trace)
      archive_contaminated_candidates!
      deduplicate_active_candidates!
      regenerated_count = regenerate ? regenerate_internal_candidates! : 0

      Result.new(
        business:,
        trace:,
        archived_action_candidate_ids: archived_action_candidate_ids.uniq,
        canceled_auto_revision_task_ids: canceled_auto_revision_task_ids.uniq,
        cancelled_action_execution_ids: cancelled_action_execution_ids.uniq,
        deduplicated_action_candidate_ids: deduplicated_action_candidate_ids.uniq,
        regenerated_count:
      )
    end

    private

    attr_reader :url, :regenerate, :archived_action_candidate_ids,
                :canceled_auto_revision_task_ids, :cancelled_action_execution_ids,
                :deduplicated_action_candidate_ids

    def business
      @business ||= Business.find_by(name: "吸えログ") ||
        Business.where("project_key = ? OR repository_name = ? OR local_project_path LIKE ?", "suelog", "suelog", "%/suelog").first
    end

    def archive_contaminated_candidates!
      contaminated_candidates.each do |candidate|
        archive_candidate!(candidate, reason: "suelog_serp_contamination_cleanup")
      end
    end

    def collect_trace_repairs!(trace)
      trace.repairs.each do |repair|
        case repair[:table]
        when "action_candidates"
          archived_action_candidate_ids << repair[:id]
        when "auto_revision_tasks"
          canceled_auto_revision_task_ids << repair[:id]
        when "action_executions"
          cancelled_action_execution_ids << repair[:id]
        end
      end
    end

    def contaminated_candidates
      business.action_candidates.where(generation_source: GENERATION_SOURCES).select do |candidate|
        contaminated_candidate?(candidate)
      end
    end

    def contaminated_candidate?(candidate)
      haystack = [
        candidate.title,
        candidate.description,
        candidate.execution_prompt,
        candidate.evaluation_reason,
        candidate.metadata.to_json
      ].join("\n")

      CONTAMINATION_PATTERNS.any? { |pattern| haystack.match?(pattern) } ||
        external_serp_url_in_metadata?(candidate)
    end

    def external_serp_url_in_metadata?(candidate)
      metadata = candidate.metadata.to_h
      urls = Array(metadata["serp_top_results"]).filter_map { |row| row.to_h["url"] } +
        Array(metadata.dig("serp_reference", "top_results")).filter_map { |row| row.to_h["url"] }
      urls.any? { |value| value.to_s.match?(%r{\Ahttps?://}i) && !value.to_s.match?(/suelog|吸えログ/i) }
    end

    def deduplicate_active_candidates!
      grouped = business.action_candidates.active_for_ranking.group_by { |candidate| duplicate_key_for(candidate) }
      grouped.each_value do |candidates|
        candidates = candidates.compact
        next if candidates.size < 2

        keep = candidates.max_by { |candidate| [ candidate.final_score.to_d, candidate.expected_profit_yen.to_i, candidate.updated_at || Time.at(0) ] }
        (candidates - [ keep ]).each do |candidate|
          archive_candidate!(candidate, reason: "duplicate_target_url_action_type", extra_metadata: { "duplicate_of_action_candidate_id" => keep.id })
          deduplicated_action_candidate_ids << candidate.id
        end
      end
    end

    def duplicate_key_for(candidate)
      metadata = candidate.metadata.to_h
      target = metadata["target_url"].presence ||
        metadata["target_url_or_identifier"].presence ||
        metadata.dig("action_plan", "target_url_or_identifier").presence ||
        metadata.dig("action_plan", "target").presence ||
        metadata.dig("evidence", "page_path").presence ||
        metadata["landing_page"].presence ||
        candidate.title
      [ target.to_s.downcase, candidate.action_type.to_s ]
    end

    def archive_candidate!(candidate, reason:, extra_metadata: {})
      return if candidate.status == "archived"

      metadata = candidate.metadata.to_h.merge(
        "archived_reason" => reason,
        "archived_at" => Time.current.iso8601,
        "archived_by" => self.class.name
      ).merge(extra_metadata)
      candidate.update_columns(status: "archived", metadata:, updated_at: Time.current)
      archived_action_candidate_ids << candidate.id
      cancel_related_tasks!(candidate, reason:)
    end

    def cancel_related_tasks!(candidate, reason:)
      candidate.auto_revision_tasks.where.not(status: %w[completed succeeded partial_succeeded failed canceled]).find_each do |task|
        task.update_columns(
          status: "canceled",
          metadata: task.metadata.to_h.merge("canceled_reason" => reason, "canceled_at" => Time.current.iso8601),
          updated_at: Time.current
        )
        canceled_auto_revision_task_ids << task.id
      end

      ActionExecution.where(action_candidate: candidate).where.not(status: %w[completed failed cancelled]).find_each do |execution|
        execution.update_columns(status: "cancelled", completed_at: Time.current, updated_at: Time.current)
        cancelled_action_execution_ids << execution.id
      end
    end

    def regenerate_internal_candidates!
      before_ids = business.action_candidates.pluck(:id).to_set
      MetricActionCandidateGenerator.new(business:).call
      business.action_candidates.where.not(id: before_ids.to_a).find_each do |candidate|
        metadata = candidate.metadata.to_h
        candidate.update_columns(
          metadata: metadata.merge("data_sources_used" => internal_data_sources_for(candidate)),
          updated_at: Time.current
        )
      end
      business.action_candidates.where.not(id: before_ids.to_a).count
    end

    def internal_data_sources_for(candidate)
      sources = Array(candidate.metadata.to_h["data_sources_used"]).presence ||
        Array(candidate.metadata.to_h.dig("evidence", "source")).presence ||
        %w[gsc ga4 internal]
      sources.map(&:to_s).map { |source| source == "business_db" ? "internal" : source }.reject { |source| source.in?(%w[serp x reddit news]) }.presence || %w[gsc ga4 internal]
    end
  end
end
