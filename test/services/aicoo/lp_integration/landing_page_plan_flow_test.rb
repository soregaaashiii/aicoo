require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPagePlanFlowTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "LP plan test",
          description: "Review before generation",
          status: "launched",
          business_type: "saas"
        )
        @campaign = @business.business_campaigns.create!(
          name: "SEO",
          campaign_type: "seo",
          status: "active"
        )
        @site = AicooAnalyticsSite.create!(
          business: @business,
          name: "Shared measurement",
          ga4_property_id: "123456789",
          gsc_site_url: "https://lp.example.com"
        )
      end

      test "purpose creates a review plan and waiting approval task without creating a landing page" do
        result = nil
        assert_no_difference [ "BusinessPrototype.count", "AicooAnalyticsSite.count", "AnalyticsSourceSetting.count" ] do
          assert_difference [ "AicooLabGenerationRun.count", "ActionCandidate.count", "AutoRevisionTask.count" ], 1 do
            result = LandingPagePlanFlow.new(
              business: @business,
              campaign: @campaign,
              attributes: { purpose: "seo" },
              strategy_builder_class: fake_strategy_builder
            ).call
          end
        end

        metadata = result.generation_run.metadata.to_h
        assert_equal "aicoo_lp_planner", metadata.fetch("pipeline")
        assert_equal "waiting_approval", metadata.fetch("pipeline_status")
        assert_equal 1, metadata.dig("review_metrics", "lp_count")
        assert_equal 48_000, metadata.dig("review_metrics", "expected_profit_yen")
        assert_equal "123456789", metadata.fetch("ga4_property_id")
        assert_equal "https://lp.example.com", metadata.fetch("gsc_site_url")
        assert_equal "waiting_approval", result.task.status
        assert_equal "lp_plan_approval", result.candidate.execution_mode
      end

      test "owner execution materializes prompts then stops every child task before lovable" do
        plan = LandingPagePlanFlow.new(
          business: @business,
          recommendations: [
            {
              purpose: "seo",
              purpose_label: "SEO",
              campaign_id: @campaign.id,
              campaign_name: @campaign.name,
              campaign_type: @campaign.campaign_type,
              missing_count: 2,
              expected_organic_visits: 30,
              expected_ad_visits: 0
            }
          ],
          strategy_builder_class: fake_strategy_builder
        ).call

        result = nil
        assert_no_difference [ "AicooAnalyticsSite.count", "AnalyticsSourceSetting.count" ] do
          assert_difference -> { @business.business_prototypes.active.external_landing_pages.count }, 2 do
            assert_difference -> { @business.auto_revision_tasks.where(status: "waiting_approval").count }, 1 do
              result = LandingPagePlanExecutor.new(
                business: @business,
                generation_run: plan.generation_run
              ).call
            end
          end
        end

        assert_equal 2, result.landing_pages.size
        assert_equal 2, result.tasks.size
        assert result.tasks.all? { |task| task.status == "waiting_approval" }
        assert result.tasks.all? { |task| task.metadata.to_h["target_deploy_target"] == "cloudflare_pages" }
        assert_equal "lovable_pending", result.generation_run.metadata.to_h["pipeline_stage"]
        assert_equal "completed", plan.task.reload.status
        assert_equal "superseded", plan.candidate.reload.status
        assert_nil result.tasks.first.sent_to_codex_at

        assert_no_difference [ "BusinessPrototype.count", "ActionCandidate.count", "AutoRevisionTask.count" ] do
          repeated = LandingPagePlanExecutor.new(
            business: @business,
            generation_run: plan.generation_run.reload
          ).call
          assert repeated.already_executed
          assert_equal result.landing_pages.map(&:id), repeated.landing_pages.map(&:id)
        end
      end

      test "normalizes externally generated Japanese text before building the review plan" do
        strategy = fake_strategy
        strategy["keywords"] = [ "梅田 喫煙 居酒屋".b ]
        builder = Class.new do
          define_method(:initialize) { |**| }
          define_method(:call) { strategy.deep_dup }
        end

        result = LandingPagePlanFlow.new(
          business: @business,
          campaign: @campaign,
          attributes: { purpose: "seo" },
          strategy_builder_class: builder
        ).call

        assert_equal Encoding::UTF_8, result.items.first.fetch("name").encoding
        assert_includes result.generation_run.prompt, "梅田 喫煙 居酒屋"
      end

      private

      def fake_strategy_builder
        strategy = fake_strategy
        Class.new do
          define_method(:initialize) { |**| }
          define_method(:call) { strategy.deep_dup }
        end
      end

      def fake_strategy
        {
          "purpose_label" => "SEO",
          "keywords" => [ "AI reception", "AI phone" ],
          "search_intent" => "compare",
          "target" => "small business",
          "persona" => "owner",
          "usp" => "24 hours",
          "headline" => "Automate calls",
          "subheadline" => "Never miss a call",
          "cta" => "Request demo",
          "faq" => [ "How long?" ],
          "comparison_table" => [],
          "structure" => [ "Hero", "Benefits", "FAQ", "CTA" ],
          "seo_title" => "AI reception",
          "meta_description" => "AI reception service",
          "image_instructions" => [ "Product screen" ],
          "color_direction" => "Brand colors",
          "design_direction" => "Operational",
          "expected_profit_yen" => 48_000,
          "expected_cv" => 8.0,
          "expected_hourly_value_yen" => 19_200,
          "estimated_work_hours" => 2.5,
          "expected_value_source" => "business_actual",
          "confidence" => 0.7,
          "reason" => "Existing business evidence"
        }
      end
    end
  end
end
