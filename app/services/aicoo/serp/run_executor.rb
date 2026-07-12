module Aicoo
  module Serp
    class RunExecutor
      def initialize(executed_by: "manual", force: false, ignore_limit: false, exploration_mode: "ai_auto", exploration_query: nil, exploration_region: nil, learning_enabled: true, new_field_ratio: 70, proven_field_ratio: 30)
        @executed_by = executed_by
        @force = force
        @ignore_limit = ignore_limit
        @exploration_mode = exploration_mode.presence || "ai_auto"
        @exploration_query = exploration_query
        @exploration_region = exploration_region
        @learning_enabled = learning_enabled
        @new_field_ratio = new_field_ratio
        @proven_field_ratio = proven_field_ratio
      end

      def call
        serp_run = nil
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::RunExecutor#call", context: memory_context) do
          planner = Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::RunPlanner", context: memory_context) do
            Aicoo::Serp::RunPlanner.new(max_total_queries: ignore_limit ? 0 : max_total_queries, force:)
          end
          serp_run = SerpRun.create!(
            status: "running",
            started_at: Time.current,
            executed_by: executed_by,
            metadata: planner.metadata.merge(
              "force" => force,
              "ignore_limit" => ignore_limit,
              "target_business_ids" => [],
              "purpose" => "new_business_exploration",
              "exploration_mode" => exploration_mode,
              "exploration_query" => exploration_query,
              "exploration_region" => exploration_region,
              "learning_enabled" => ActiveModel::Type::Boolean.new.cast(learning_enabled),
              "new_field_ratio" => new_field_ratio.to_i,
              "proven_field_ratio" => proven_field_ratio.to_i,
              "legacy_business_serp_disabled" => true
            ).compact
          )

          result = Aicoo::Serp::ScanRunner.new(
            serp_run:,
            force:,
            max_total_queries: ignore_limit ? nil : max_total_queries,
            max_queries_per_business: max_queries_per_business,
            exploration_mode:,
            exploration_query:,
            exploration_region:
          ).call
          serp_run.finish_from_result!(result)
          discovery_result = run_new_business_discovery!(serp_run)
          existing_candidates = []
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
        end
        serp_run
      rescue StandardError => e
        serp_run&.fail!(e)
        raise
      end

      private

      attr_reader :executed_by, :force, :ignore_limit, :exploration_mode, :exploration_query, :exploration_region, :learning_enabled, :new_field_ratio, :proven_field_ratio

      def memory_context(extra = {})
        {
          executed_by:,
          force:,
          ignore_limit:,
          exploration_mode:,
          exploration_region:,
          learning_enabled: ActiveModel::Type::Boolean.new.cast(learning_enabled),
          new_field_ratio: new_field_ratio.to_i,
          proven_field_ratio: proven_field_ratio.to_i
        }.merge(extra).compact
      end

      def settings
        Aicoo::Serp::Scheduler.settings
      end

      def market_exploration_business
        Business.find_or_create_by!(name: "AICOO Market Exploration") do |business|
          business.description = "SERP新規事業探索の保存用システムBusiness"
          business.status = "launched"
          business.lifecycle_stage = "idea"
          business.business_type = "exploration"
          business.category = "market_exploration" if business.respond_to?(:category=)
          business.source = "system"
          business.created_by_aicoo = true
          business.launched = false
          business.daily_run_enabled = false
          business.serp_enabled = true
          business.auto_revision_mode = "manual"
          business.auto_build_enabled = false
          business.auto_deploy_mode = "manual"
          business.resource_status = "archived"
        end
      end

      def max_total_queries
        settings["daily_query_limit"].to_i.positive? ? settings["daily_query_limit"].to_i : 30
      end

      def max_queries_per_business
        Aicoo::Serp::ScanPlan.configured_limit
      end

      def run_new_business_discovery!(serp_run)
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::NewBusinessDiscoveryGenerator#call", context: memory_context(serp_run_id: serp_run.id)) do
          Aicoo::Serp::NewBusinessDiscoveryGenerator.new(serp_run:).call
        end
      rescue StandardError => e
        Rails.logger.warn("[SERP] new business discovery skipped serp_run_id=#{serp_run.id} #{e.class}: #{e.message}")
        Aicoo::Serp::NewBusinessDiscoveryGenerator::Result.new(
          candidates: [],
          created_count: 0,
          duplicate_count: 0,
          blank_query_count: 0,
          no_result_count: 0,
          failed_count: 1,
          existing_improvement_count: 0,
          serp_analyses_checked: 0,
          serp_results_checked: 0,
          errors: [ { "error_class" => e.class.name, "error_message" => e.message } ]
        )
      end

      def publish_new_business_candidates!(serp_run, candidates)
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::AutoNewBusinessPublisher.call", context: memory_context(serp_run_id: serp_run.id, candidate_count: candidates.size)) do
          Aicoo::Serp::AutoNewBusinessPublisher.call(serp_run:, candidates:, source: "serp_run")
        end
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
          "blank_query_count" => result.blank_query_count,
          "no_result_count" => result.no_result_count,
          "failed_count" => result.failed_count,
          "existing_business_improvement_count" => result.existing_improvement_count,
          "serp_analyses_checked" => result.serp_analyses_checked,
          "serp_results_checked" => result.serp_results_checked,
          "candidate_ids" => result.candidates.map(&:id),
          "business_ids" => result.candidates.filter_map(&:business_id),
          "errors" => result.errors.first(5)
        }
      end
    end
  end
end
