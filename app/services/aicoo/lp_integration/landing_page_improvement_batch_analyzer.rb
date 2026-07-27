module Aicoo
  module LpIntegration
    class LandingPageImprovementBatchAnalyzer
      Result = Data.define(:business_count, :landing_page_count, :analyzed_count, :candidate_count, :task_count, :skipped_count, :failed_count, :candidate_ids, :task_ids, :errors)

      def self.call
        new.call
      end

      def call
        stats = empty_stats
        target_businesses.find_each do |business|
          analyze_business(business, stats)
        end
        Result.new(**stats)
      end

      private

      def target_businesses
        Business.where(id: BusinessPrototype.active.external_landing_pages.select(:business_id))
      end

      def analyze_business(business, stats)
        landing_pages = business.business_prototypes.active.external_landing_pages.select do |landing_page|
          landing_page.cloudflare_published?
        end
        return if landing_pages.empty?

        stats[:business_count] += 1
        stats[:landing_page_count] += landing_pages.size
        snapshots = Aicoo::Lovable::LandingPageAnalyticsReader.latest_snapshots_for(business)
        landing_pages.each { |landing_page| analyze_landing_page(business, landing_page, snapshots, stats) }
      end

      def analyze_landing_page(business, landing_page, snapshots, stats)
        result = LandingPageImprovementAnalyzer.new(business:, landing_page:, snapshots:).call
        mark_pipeline_analyzed(landing_page, result.metrics)
        stats[:analyzed_count] += 1
        if result.candidate
          stats[:candidate_count] += 1
          stats[:candidate_ids] << result.candidate.id
          create_improvement_task(business, landing_page, snapshots, result, stats)
        else
          stats[:skipped_count] += 1
        end
      rescue StandardError => e
        stats[:failed_count] += 1
        stats[:errors] << "LP ##{landing_page.id}: #{e.class}: #{e.message}"
        Rails.logger.warn("[LandingPageImprovementBatchAnalyzer] business_id=#{business.id} landing_page_id=#{landing_page.id} error=#{e.class}: #{e.message}")
      end

      def create_improvement_task(business, landing_page, snapshots, analysis, stats)
        return if analysis.candidate.final_expected_value_yen.to_d < minimum_expected_profit_yen

        flow = LandingPageImprovementFlow.new(
          business:,
          landing_page:,
          snapshots:,
          analysis:
        ).call
        return unless flow.created

        stats[:task_count] += 1
        stats[:task_ids] << flow.task.id
      end

      def minimum_expected_profit_yen
        @minimum_expected_profit_yen ||= AicooAutoRevisionSetting.current.minimum_final_score.to_d
      end

      def mark_pipeline_analyzed(landing_page, metrics)
        run = AicooLabGenerationRun.find_by(id: landing_page.metadata.to_h["lovable_generation_run_id"])
        return unless run&.metadata.to_h&.dig("pipeline") == "lovable"

        now = Time.current.iso8601
        learning_status = metrics["learning"].to_h["status"].presence || "baseline_analyzed"
        run_metadata = run.metadata.to_h.merge(
          "pipeline_status" => "improvement_waiting",
          "measurement_checked_at" => now,
          "learning_status" => learning_status,
          "measurement_sources" => {
            "ga4" => metrics.dig("ga4", "available") == true ? "available" : "waiting",
            "gsc" => metrics.dig("gsc", "available") == true ? "available" : "waiting"
          }
        )
        run_metadata["learning_completed_at"] = now if learning_status == "evaluated"
        run.update!(metadata: run_metadata)
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "planning_status" => "improvement_pending",
          "pipeline_stage" => "improvement_pending",
          "pipeline_stages" => LandingPagePipelineState.build(current: "improvement_pending", approval_required: false)
        ))
      end

      def empty_stats
        {
          business_count: 0,
          landing_page_count: 0,
          analyzed_count: 0,
          candidate_count: 0,
          task_count: 0,
          skipped_count: 0,
          failed_count: 0,
          candidate_ids: [],
          task_ids: [],
          errors: []
        }
      end
    end
  end
end
