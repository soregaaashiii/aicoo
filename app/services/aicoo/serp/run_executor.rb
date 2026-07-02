module Aicoo
  module Serp
    class RunExecutor
      def initialize(executed_by: "manual", force: false, serp_query: nil)
        @executed_by = executed_by
        @force = force
        @serp_query = serp_query
      end

      def call
        serp_run = SerpRun.create!(
          status: "running",
          started_at: Time.current,
          executed_by: executed_by,
          metadata: {
            "force" => force,
            "serp_query_id" => serp_query&.id
          }.compact
        )

        result = Aicoo::Serp::ScanRunner.new(
          serp_run:,
          force:,
          single_serp_query: serp_query,
          max_total_queries: max_total_queries,
          max_queries_per_business: max_queries_per_business
        ).call
        run_priority_learning!
        serp_run.finish_from_result!(result)
        candidates = run_integrated_decision!(serp_run)
        serp_run.update!(candidate_count: candidates.size) if candidates
        serp_run
      rescue StandardError => e
        serp_run&.fail!(e)
        raise
      end

      private

      attr_reader :executed_by, :force, :serp_query

      def settings
        Aicoo::Serp::Scheduler.settings
      end

      def max_total_queries
        return 1 if serp_query

        settings["daily_query_limit"].to_i.positive? ? settings["daily_query_limit"].to_i : 30
      end

      def max_queries_per_business
        return 1 if serp_query

        Aicoo::Serp::ScanPlan.configured_limit
      end

      def run_priority_learning!
        Aicoo::Serp::PriorityUpdater.update_all!
      rescue StandardError => e
        Rails.logger.warn("[SERP] priority learning skipped #{e.class}: #{e.message}")
      end

      def run_integrated_decision!(serp_run)
        Aicoo::IntegratedDecisionEngine.new(serp_run:).generate_unified_candidates!
      rescue StandardError => e
        Rails.logger.warn("[SERP] integrated decision skipped serp_run_id=#{serp_run.id} #{e.class}: #{e.message}")
      end
    end
  end
end
