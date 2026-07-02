module Aicoo
  module Serp
    class ScanStatus
      Result = Data.define(
        :provider,
        :limit,
        :api_key_configured,
        :last_scanned_at,
        :last_duration_seconds,
        :target_business_count,
        :candidate_keyword_count,
        :estimated_api_calls,
        :estimated_cost_yen,
        :monthly_budget_yen,
        :current_month_spend_yen,
        :projected_month_spend_yen,
        :budget_exceeded,
        :limit_warning_level,
        :limit_warning_message,
        :execution_status,
        :latest_analysis,
        :running_started_at,
        :current_business_name,
        :completed_count,
        :failed_count,
        :latest_result_count,
        :latest_query_count,
        :latest_estimated_cost_yen
      )

      def call
        plan = Aicoo::Serp::ScanPlan.new.call
        Result.new(
          provider: current_provider,
          limit: plan.limit,
          api_key_configured: api_key_configured?,
          last_scanned_at: latest_analysis&.analyzed_at,
          last_duration_seconds: latest_duration_seconds,
          target_business_count: target_businesses.size,
          candidate_keyword_count: plan.candidate_keyword_count,
          estimated_api_calls: plan.estimated_api_calls,
          estimated_cost_yen: plan.estimated_cost_yen,
          monthly_budget_yen: plan.monthly_budget_yen,
          current_month_spend_yen: plan.current_month_spend_yen,
          projected_month_spend_yen: plan.projected_month_spend_yen,
          budget_exceeded: plan.budget_exceeded,
          limit_warning_level: plan.limit_warning_level,
          limit_warning_message: plan.limit_warning_message,
          execution_status: execution_status,
          latest_analysis:,
          running_started_at: running_analyses.minimum(:analyzed_at),
          current_business_name: running_analyses.includes(:business).order(analyzed_at: :desc, created_at: :desc).first&.business&.name,
          completed_count: latest_batch_analyses.count { |analysis| analysis.status == "success" },
          failed_count: latest_batch_analyses.count { |analysis| analysis.status == "failed" },
          latest_result_count: latest_batch_analyses.sum { |analysis| analysis.result_count.to_i },
          latest_query_count: latest_batch_analyses.size,
          latest_estimated_cost_yen: latest_estimated_cost_yen
        )
      end

      private

      def current_provider
        ENV["AICOO_SERP_PROVIDER"].presence || "serper"
      end

      def api_key_configured?
        ENV["SERPER_API_KEY"].present? || DataSourceCostProfile.find_by(source_key: "serp")&.api_key.present?
      end

      def target_businesses
        @target_businesses ||= Business.real_businesses
                                      .where(status: "launched", serp_enabled: true)
                                      .includes(:business_data_source_settings, :business_serp_keywords, :serp_queries)
                                      .order(:name)
                                      .to_a
      end

      def latest_analysis
        @latest_analysis ||= SerpAnalysis.joins(:business)
                                         .merge(Business.real_businesses)
                                         .order(analyzed_at: :desc, created_at: :desc)
                                         .first
      end

      def execution_status
        return "SERP走査中" if running_analyses.exists?
        return "SERP走査に失敗しました" if latest_analysis&.status == "failed"
        return "SERP走査が完了しました" if latest_analysis&.status == "success"

        "未実行"
      end

      def queries_for(business)
        Aicoo::Serp::ScanRunner.queries_for_business(business)
      end

      def running_analyses
        @running_analyses ||= SerpAnalysis.running.joins(:business).merge(Business.real_businesses)
      end

      def latest_batch_id
        latest_analysis&.raw_summary.to_h["scan_batch_id"]
      end

      def latest_batch_analyses
        @latest_batch_analyses ||= if latest_batch_id.present?
          SerpAnalysis.joins(:business)
                      .merge(Business.real_businesses)
                      .where("serp_analyses.raw_summary ->> 'scan_batch_id' = ?", latest_batch_id)
                      .to_a
        elsif latest_analysis
          [ latest_analysis ]
        else
          []
        end
      end

      def latest_duration_seconds
        times = latest_batch_analyses.filter_map do |analysis|
          [
            parse_time(analysis.raw_summary.to_h["scan_started_at"]) || analysis.analyzed_at,
            parse_time(analysis.raw_summary.to_h["scan_finished_at"]) || analysis.updated_at
          ]
        end.flatten.compact
        return if times.empty?

        (times.max - times.min).round(2)
      end

      def latest_estimated_cost_yen
        return 0 if latest_batch_analyses.empty?

        limit = latest_batch_analyses.first.raw_summary.to_h["limit"].presence || Aicoo::Serp::ScanPlan.configured_limit
        plan = Aicoo::Serp::ScanPlan.new.call(limit:)
        return 0 if plan.candidate_keyword_count.to_i.zero?

        (plan.estimated_cost_yen.to_d * (latest_batch_analyses.size.to_d / plan.candidate_keyword_count.to_d)).round.to_i
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
