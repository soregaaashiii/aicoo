require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPageCreationFlowTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "AI受付",
          description: "電話対応をAIで自動化するサービス",
          status: "building",
          business_type: "saas"
        )
        @campaign = @business.business_campaigns.create!(
          name: "Google Ads",
          campaign_type: "google_ads",
          status: "active"
        )
      end

      test "purpose only creates strategy prompt candidate and waiting approval task" do
        result = nil
        assert_difference [
          "BusinessPrototype.count",
          "AicooLabGenerationRun.count",
          "ActionCandidate.count",
          "AutoRevisionTask.count"
        ], 1 do
          result = LandingPageCreationFlow.new(
            business: @business,
            campaign: @campaign,
            attributes: { purpose: "google_ads" },
            strategy_builder_class: fake_strategy_builder
          ).call
        end

        landing_page = result.landing_page.reload
        assert_equal @campaign, landing_page.business_campaign
        assert_equal "testing", landing_page.landing_page_public_status
        assert_equal "Google広告", landing_page.metadata.to_h["creation_purpose_label"]
        assert_equal "waiting_approval", landing_page.metadata.to_h["planning_status"]
        assert_equal 48_000, landing_page.metadata.to_h["expected_profit_yen"]

        run = result.generation_run.reload
        assert_equal landing_page.id, run.metadata.to_h["landing_page_prototype_id"]
        assert_equal "prompt_ready", run.metadata.to_h["pipeline_status"]
        assert_includes run.prompt, "資料請求する"
        assert_includes run.prompt, "ファーストビュー"

        assert_equal "build_lp", result.candidate.action_type
        assert_equal "lovable_generation", result.candidate.execution_mode
        assert_equal "waiting_approval", result.task.status
        assert_equal "lovable_pending", result.task.metadata.to_h["pipeline_stage"]
        assert_equal false, result.task.metadata.to_h["auto_deploy_enabled"]
        assert_equal "cloudflare_pages", result.task.metadata.to_h["target_deploy_target"]
      end

      private

      def fake_strategy_builder
        strategy = {
          "purpose_label" => "Google広告",
          "keywords" => [ "AI 電話受付" ],
          "search_intent" => "比較して申し込みたい",
          "target" => "電話対応に困る中小企業",
          "persona" => "少人数企業の経営者",
          "usp" => "24時間対応",
          "headline" => "電話対応をAIへ",
          "subheadline" => "取りこぼしを減らします",
          "cta" => "資料請求する",
          "faq" => [ "導入期間は？" ],
          "comparison_table" => [],
          "structure" => [ "ファーストビュー", "導入効果", "FAQ", "最終CTA" ],
          "seo_title" => "AI電話受付",
          "meta_description" => "AI電話受付の案内",
          "image_instructions" => [ "利用画面を表示" ],
          "color_direction" => "ブランドカラー",
          "design_direction" => "業務向け",
          "expected_profit_yen" => 48_000,
          "expected_cv" => 8.0,
          "expected_hourly_value_yen" => 19_200,
          "estimated_work_hours" => 2.5,
          "expected_value_source" => "business_actual",
          "confidence" => 0.7,
          "reason" => "広告流入と既存実績を基に生成"
        }
        Class.new do
          define_method(:initialize) { |**| }
          define_method(:call) { strategy }
        end
      end
    end
  end
end
