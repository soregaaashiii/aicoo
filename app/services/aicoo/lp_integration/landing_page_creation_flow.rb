module Aicoo
  module LpIntegration
    class LandingPageCreationFlow
      Result = Data.define(:landing_page, :strategy, :generation_run, :candidate, :task)

      def initialize(business:, campaign:, attributes:, strategy_builder_class: LandingPageStrategyBuilder)
        @business = business
        @campaign = campaign
        @attributes = attributes.to_h.deep_stringify_keys
        @strategy_builder_class = strategy_builder_class
      end

      def call
        validate!
        strategy = strategy_builder_class.new(
          business:,
          campaign:,
          purpose: attributes.fetch("purpose"),
          notes: attributes["notes"],
          advanced: advanced_attributes
        ).call

        result = nil
        Business.transaction do
          landing_page = create_landing_page!(strategy)
          prepared = Aicoo::Lovable::LandingPagePipeline.new.prepare_external_create!(
            business:,
            landing_page_prototype: landing_page,
            strategy:
          )
          candidate = create_candidate!(landing_page, strategy, prepared.generation_run)
          task = create_task!(landing_page, strategy, prepared.generation_run, candidate)
          stamp_records!(landing_page, prepared.generation_run, candidate, task, strategy)
          result = Result.new(landing_page:, strategy:, generation_run: prepared.generation_run, candidate:, task:)
        end
        result
      end

      private

      attr_reader :business, :campaign, :attributes, :strategy_builder_class

      def validate!
        raise ArgumentError, "このBusinessのCampaignではありません。" unless campaign.business_id == business.id
        raise ArgumentError, "作成目的を選択してください。" unless attributes["purpose"].in?(LandingPageStrategyBuilder::PURPOSES)
      end

      def create_landing_page!(strategy)
        landing_page = LandingPageRegistry.new(business:).save!(
          campaign_id: campaign.id,
          name: attributes["name"].presence || generated_name,
          source_type: "manual",
          public_status: "testing",
          cta: strategy["cta"],
          improvement_target: strategy["reason"]
        )
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "creation_purpose" => attributes.fetch("purpose"),
          "creation_purpose_label" => LandingPageStrategyBuilder::PURPOSES.fetch(attributes.fetch("purpose")),
          "creation_notes" => attributes["notes"].presence,
          "lp_strategy" => strategy,
          "expected_profit_yen" => strategy["expected_profit_yen"].to_i,
          "expected_cv" => strategy["expected_cv"].to_f,
          "expected_hourly_value_yen" => strategy["expected_hourly_value_yen"].to_i,
          "improvement_status" => "prompt_review",
          "planning_status" => "prompt_ready"
        ).compact)
        landing_page
      end

      def create_candidate!(landing_page, strategy, generation_run)
        business.action_candidates.create!(
          title: "#{landing_page.landing_page_name}をLovableで生成する",
          description: "AICOOが#{strategy['reason']}Lovable Promptを生成し、Ownerレビュー後に制作します。",
          evaluation_reason: strategy["reason"],
          action_type: "build_lp",
          generation_source: "ai_business",
          department: "revenue",
          status: "proposal",
          immediate_value_yen: strategy["expected_profit_yen"].to_i,
          expected_hours: strategy["estimated_work_hours"].to_d,
          success_probability: strategy["confidence"].to_d,
          confidence_score: (strategy["confidence"].to_d * 100).round,
          data_confidence_score: (strategy["confidence"].to_d * 100).round,
          execution_prompt: generation_run.prompt,
          metadata: {
            "workflow_type" => "external_lp_creation",
            "execution_mode" => "lovable_generation",
            "source_system" => "aicoo_lp_strategy",
            "landing_page_id" => landing_page.id,
            "campaign_id" => campaign.id,
            "lovable_generation_run_id" => generation_run.id,
            "target_metric" => "lp_conversion_rate",
            "expected_profit_yen" => strategy["expected_profit_yen"].to_i,
            "expected_cv" => strategy["expected_cv"].to_f,
            "expected_hourly_value_yen" => strategy["expected_hourly_value_yen"].to_i,
            "lp_strategy" => strategy,
            "owner_approval_required" => true,
            "auto_revision" => false,
            "auto_merge" => false,
            "auto_deploy" => false,
            "target_deploy_target" => "cloudflare_pages",
            "service_repository_protected" => true
          }
        )
      end

      def create_task!(landing_page, strategy, generation_run, candidate)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: "lovable-lp-#{landing_page.id}",
          target_repository_type: "static_site",
          title: candidate.title,
          execution_prompt: generation_run.prompt,
          priority_score: candidate.final_expected_value_yen.to_i,
          generated_by: "aicoo_lp_strategy",
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "external_lp_creation",
            "landing_page_prototype_id" => landing_page.id,
            "campaign_id" => campaign.id,
            "lovable_generation_run_id" => generation_run.id,
            "pipeline_stage" => "prompt_review",
            "approval_required_reason" => "Lovable送信前にLP戦略とPromptのOwner確認が必要です。",
            "manual_approval_required" => true,
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "target_deploy_target" => "cloudflare_pages",
            "service_repository_protected" => true,
            "expected_profit_yen" => strategy["expected_profit_yen"].to_i
          }
        )
      end

      def stamp_records!(landing_page, generation_run, candidate, task, strategy)
        generation_run.update!(metadata: generation_run.metadata.to_h.merge(
          "action_candidate_id" => candidate.id,
          "auto_revision_task_id" => task.id,
          "expected_profit_yen" => strategy["expected_profit_yen"].to_i
        ))
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "lovable_generation_run_id" => generation_run.id,
          "action_candidate_id" => candidate.id,
          "auto_revision_task_id" => task.id,
          "planning_status" => "waiting_approval"
        ))
      end

      def generated_name
        sequence = campaign.landing_pages.active.count + 1
        "#{campaign.name} #{LandingPageStrategyBuilder::PURPOSES.fetch(attributes.fetch('purpose'))} LP#{sequence}"
      end

      def advanced_attributes
        attributes.fetch("advanced", {}).to_h.deep_stringify_keys
      end
    end
  end
end
