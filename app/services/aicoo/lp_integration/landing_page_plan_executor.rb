module Aicoo
  module LpIntegration
    class LandingPagePlanExecutor
      Result = Data.define(:generation_run, :landing_pages, :tasks, :already_executed)

      def initialize(business:, generation_run:)
        @business = business
        @generation_run = generation_run
      end

      def call
        validate!
        return existing_result if metadata["executed_at"].present?

        landing_pages = []
        tasks = []
        Business.transaction do
          Array(metadata.fetch("plan_items")).each do |item|
            values = item.to_h.deep_stringify_keys
            campaign = campaign_for(values)
            result = LandingPageCreationFlow.new(
              business:,
              campaign:,
              attributes: {
                "purpose" => values.fetch("purpose"),
                "name" => values["name"],
                "notes" => values["notes"],
                "advanced" => values.fetch("advanced", {})
              },
              strategy: values.fetch("strategy")
            ).call
            landing_pages << result.landing_page
            tasks << result.task
          end
          complete_plan!(landing_pages, tasks)
        end
        Result.new(generation_run: generation_run.reload, landing_pages:, tasks:, already_executed: false)
      end

      private

      attr_reader :business, :generation_run

      def metadata
        @metadata ||= generation_run.metadata.to_h.deep_stringify_keys
      end

      def validate!
        unless metadata["pipeline"] == "aicoo_lp_planner" && metadata["business_id"].to_i == business.id
          raise ActiveRecord::RecordNotFound, "LP生成計画が見つかりません。"
        end
        raise ArgumentError, "LP生成計画に対象LPがありません。" if Array(metadata["plan_items"]).empty?
      end

      def campaign_for(item)
        campaign = business.business_campaigns.active.find_by(id: item["campaign_id"])
        return campaign if campaign

        purpose = item.fetch("purpose")
        name = item["campaign_name"].presence || LandingPageStrategyBuilder::PURPOSES.fetch(purpose)
        business.business_campaigns.find_or_create_by!(name:) do |record|
          record.campaign_type = item["campaign_type"].presence ||
            BusinessLandingPagePlanner::PURPOSE_CAMPAIGN_TYPES.fetch(purpose)
          record.status = "active"
          record.metadata = { "planner_purpose" => purpose }
        end
      end

      def complete_plan!(landing_pages, tasks)
        now = Time.current
        generation_run.update!(
          status: "succeeded",
          generated_count: landing_pages.size,
          finished_at: now,
          metadata: metadata.merge(
            "pipeline_status" => "lovable_pending",
            "pipeline_stage" => "lovable_pending",
            "pipeline_stages" => LandingPagePipelineState.build(current: "lovable_pending"),
            "landing_page_prototype_ids" => landing_pages.map(&:id),
            "child_auto_revision_task_ids" => tasks.map(&:id),
            "executed_at" => now.iso8601
          )
        )
        candidate = business.action_candidates.find_by(id: metadata["action_candidate_id"])
        candidate&.update!(
          status: "superseded",
          metadata: candidate.metadata.to_h.merge(
            "superseded_reason" => "lp_plan_materialized",
            "superseded_at" => now.iso8601
          )
        )
        task = business.auto_revision_tasks.find_by(id: metadata["auto_revision_task_id"])
        task&.update!(
          status: "completed",
          finished_at: now,
          metadata: task.metadata.to_h.merge(
            "pipeline_stage" => "lovable_pending",
            "approved_for_generation_at" => now.iso8601,
            "child_auto_revision_task_ids" => tasks.map(&:id)
          )
        )
      end

      def existing_result
        landing_pages = business.business_prototypes.where(id: Array(metadata["landing_page_prototype_ids"]))
        tasks = business.auto_revision_tasks.where(id: Array(metadata["child_auto_revision_task_ids"]))
        Result.new(generation_run:, landing_pages: landing_pages.to_a, tasks: tasks.to_a, already_executed: true)
      end
    end
  end
end
