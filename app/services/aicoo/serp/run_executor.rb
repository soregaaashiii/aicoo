module Aicoo
  module Serp
    class RunExecutor
      def initialize(executed_by: "manual", force: false, serp_query: nil, target_businesses: nil, ignore_limit: false)
        @executed_by = executed_by
        @force = force
        @serp_query = serp_query
        @target_businesses = target_businesses
        @ignore_limit = ignore_limit
      end

      def call
        planner = Aicoo::Serp::RunPlanner.new(
          target_businesses: target_businesses,
          max_total_queries: ignore_limit ? 0 : max_total_queries,
          force:,
          single_serp_query: serp_query
        )
        serp_run = SerpRun.create!(
          status: "running",
          started_at: Time.current,
          executed_by: executed_by,
          metadata: planner.metadata.merge(
            "force" => force,
            "ignore_limit" => ignore_limit,
            "serp_query_id" => serp_query&.id,
            "target_business_ids" => target_businesses.map(&:id)
          ).compact
        )

        result = Aicoo::Serp::ScanRunner.new(
          serp_run:,
          force:,
          single_serp_query: serp_query,
          target_businesses: target_businesses,
          allowed_serp_query_ids: planner.run_query_ids,
          max_total_queries: ignore_limit ? nil : max_total_queries,
          max_queries_per_business: max_queries_per_business
        ).call
        run_priority_learning!
        serp_run.finish_from_result!(result)
        discovery_result = run_new_business_discovery!(serp_run)
        existing_candidates = run_integrated_decision!(serp_run)
        candidates = discovery_result.candidates + existing_candidates
        publication_result = publish_new_business_candidates!(serp_run, candidates)
        serp_run.update!(
          candidate_count: candidates.size,
          metadata: serp_run.metadata.to_h.merge(
            "new_business_discovery" => discovery_metadata(discovery_result),
            "existing_business_improvement_count" => existing_candidates.size,
            "auto_new_business_publication" => publication_metadata(publication_result)
          )
        ) if candidates
        serp_run
      rescue StandardError => e
        serp_run&.fail!(e)
        raise
      end

      private

      attr_reader :executed_by, :force, :serp_query, :ignore_limit

      def settings
        Aicoo::Serp::Scheduler.settings
      end

      def target_businesses
        @target_businesses ||= begin
          return [ serp_query.business ] if serp_query

          Business.real_businesses.where(status: "launched", serp_enabled: true)
                  .includes(:business_data_source_settings, :business_serp_keywords, :serp_queries)
                  .order(:name)
                  .to_a
        end
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
        []
      end

      def run_new_business_discovery!(serp_run)
        Aicoo::Serp::NewBusinessDiscoveryGenerator.new(serp_run:).call
      rescue StandardError => e
        Rails.logger.warn("[SERP] new business discovery skipped serp_run_id=#{serp_run.id} #{e.class}: #{e.message}")
        Aicoo::Serp::NewBusinessDiscoveryGenerator::Result.new(
          candidates: [],
          created_count: 0,
          duplicate_count: 0,
          failed_count: 1,
          existing_improvement_count: 0,
          errors: [ { "error_class" => e.class.name, "error_message" => e.message } ]
        )
      end

      def publish_new_business_candidates!(serp_run, candidates)
        Aicoo::Serp::AutoNewBusinessPublisher.call(serp_run:, candidates:, source: "serp_run")
      rescue StandardError => e
        Rails.logger.warn("[SERP] auto new business publication skipped serp_run_id=#{serp_run.id} #{e.class}: #{e.message}")
        nil
      end

      def publication_metadata(result)
        return { "status" => "skipped", "reason" => "publisher_not_run" } unless result

        {
          "status" => result.failed_count.to_i.positive? ? "partial_failed" : "success",
          "checked_count" => result.checked_count,
          "business_created_count" => result.business_created_count,
          "business_linked_count" => result.business_linked_count,
          "lp_created_count" => result.lp_created_count,
          "lp_published_count" => result.lp_published_count,
          "skipped_count" => result.skipped_count,
          "failed_count" => result.failed_count,
          "business_ids" => result.business_ids,
          "landing_page_ids" => result.landing_page_ids,
          "errors" => result.errors.first(5)
        }
      end

      def discovery_metadata(result)
        {
          "status" => result.failed_count.to_i.positive? ? "partial_failed" : "success",
          "new_business_candidate_count" => result.created_count,
          "duplicate_count" => result.duplicate_count,
          "failed_count" => result.failed_count,
          "existing_business_improvement_count" => result.existing_improvement_count,
          "candidate_ids" => result.candidates.map(&:id),
          "business_ids" => result.candidates.filter_map(&:business_id),
          "errors" => result.errors.first(5)
        }
      end
    end
  end
end
