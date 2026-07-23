require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPageImprovementAnalyzerTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "LP改善分析テスト",
          status: "launched",
          lifecycle_stage: "production",
          business_type: "landing_page"
        )
        @landing_page = LandingPageRegistry.new(business: @business).save!(
          name: "広告LP",
          source_type: "github",
          repository_url: "https://github.com/example/ad-lp",
          branch: "main",
          url: "https://lp.example.com/lp/ad",
          ga4_page_path: "/lp/ad",
          public_status: "published"
        )
        @business.business_metric_dailies.create!(
          recorded_on: Date.current,
          sessions: 100,
          conversions: 10,
          impressions: 1_000,
          clicks: 100
        )
        create_metric_snapshot("ga4", {
          "date" => Date.current.strftime("%Y%m%d"),
          "pagePath" => "/lp/ad",
          "screenPageViews" => 120,
          "activeUsers" => 80,
          "sessions" => 100,
          "eventCount" => 200,
          "keyEvents" => 2
        })
        create_metric_snapshot("gsc", {
          "date" => Date.current.iso8601,
          "page" => "https://lp.example.com/lp/ad",
          "impressions" => 400,
          "clicks" => 20,
          "position" => 12
        })
      end

      test "creates a landing page candidate with yen cv and hourly expectations" do
        assert_difference -> { @business.action_candidates.where(generation_source: "lp_learning").count }, 1 do
          result = LandingPageImprovementAnalyzer.new(business: @business, landing_page: @landing_page).call
          assert result.candidate
        end

        candidate = @business.action_candidates.where(generation_source: "lp_learning").last
        expected_value = candidate.metadata.to_h.fetch("lp_expected_value")
        assert_equal "external_lp_improvement", candidate.metadata.to_h["workflow_type"]
        assert_equal @landing_page.id, candidate.metadata.to_h["landing_page_id"]
        assert_equal "https://github.com/example/ad-lp", candidate.metadata.to_h["target_repository_url"]
        assert_equal "cloudflare_pages", candidate.metadata.to_h["target_deploy_target"]
        assert_operator expected_value.fetch("expected_profit_yen"), :>, 0
        assert_operator expected_value.fetch("expected_cv").to_d, :>, 2
        assert_operator expected_value.fetch("expected_hourly_value_yen"), :>, 0
        assert_operator candidate.final_expected_value_yen, :>, 0
        assert_operator @landing_page.reload.metadata.to_h["expected_profit_yen"], :>, 0
      end

      test "does not duplicate a candidate for unchanged source snapshots" do
        first = LandingPageImprovementAnalyzer.new(business: @business, landing_page: @landing_page).call
        assert_no_difference -> { @business.action_candidates.where(generation_source: "lp_learning").count } do
          second = LandingPageImprovementAnalyzer.new(business: @business, landing_page: @landing_page).call
          assert_equal first.candidate.id, second.candidate.id
        end
      end

      test "batch analyzer uses shared snapshots and analyzes published landing pages" do
        LandingPageRegistry.new(business: @business).save!(
          name: "下書きLP",
          source_type: "public_url",
          url: "https://lp.example.com/draft",
          ga4_page_path: "/draft",
          public_status: "draft"
        )

        result = LandingPageImprovementBatchAnalyzer.call

        assert_equal 1, result.business_count
        assert_equal 1, result.landing_page_count
        assert_equal 1, result.analyzed_count
        assert_equal 1, result.candidate_count
        assert_equal 0, result.failed_count
        assert_equal @business.action_candidates.where(generation_source: "lp_learning").pluck(:id), result.candidate_ids
      end

      test "improvement flow creates a waiting approval task for a published landing page" do
        result = nil
        assert_difference [ "ActionCandidate.count", "AutoRevisionTask.count", "BusinessPrototype.count" ], 1 do
          result = LandingPageImprovementFlow.new(business: @business, landing_page: @landing_page).call
        end

        assert result.created
        assert_equal "waiting_approval", result.task.reload.status
        assert_equal "external_lp_improvement", result.task.metadata.to_h["workflow_type"]
        assert_equal "cloudflare_pages", result.task.effective_deploy_target
        assert_equal "LP公開前にOwner確認が必要です。", result.task.metadata.to_h["approval_required_reason"]
        assert_equal false, result.task.metadata.to_h["auto_deploy_enabled"]
        variant = BusinessPrototype.find(result.task.metadata.to_h.fetch("landing_page_prototype_id"))
        assert_equal "testing", variant.landing_page_public_status
        assert_equal @landing_page.id, variant.metadata.to_h["ab_source_landing_page_id"]
        assert_equal "B", variant.landing_page_ab_test["variant"]
        assert_equal "published", @landing_page.reload.landing_page_public_status
        assert_includes result.task.execution_prompt, "現行LP A"
        assert_includes result.task.execution_prompt, "上書きしない"
      end

      test "batch analyzer creates a waiting approval task only above the yen threshold" do
        AicooAutoRevisionSetting.current.update!(minimum_final_score: 1)

        result = LandingPageImprovementBatchAnalyzer.call

        assert_equal 1, result.task_count
        assert_equal 1, result.task_ids.size
        assert_equal "waiting_approval", AutoRevisionTask.find(result.task_ids.first).status
      end

      test "improvement flow rejects a landing page that is not published" do
        LandingPageRegistry.new(business: @business).update_status!(@landing_page.id, "testing")

        assert_no_difference [ "ActionCandidate.count", "AutoRevisionTask.count" ] do
          error = assert_raises(ArgumentError) do
            LandingPageImprovementFlow.new(business: @business, landing_page: @landing_page).call
          end
          assert_equal "公開中のLPだけが改善対象です。", error.message
        end
      end

      private

      def create_metric_snapshot(source_type, row)
        source = @business.data_sources.create!(name: "#{source_type.upcase} test", source_type:, status: "active")
        data_import = source.data_imports.create!(
          filename: "#{source_type}.json",
          content_type: "application/json",
          raw_text: { "rows" => [ row ] }.to_json,
          row_count: 1,
          imported_at: Time.current
        )
        AicooDataSnapshot.create!(
          source_type:,
          source_id: data_import.id,
          captured_at: Time.current,
          payload: {
            "business_id" => @business.id,
            "snapshot_status" => "active",
            "rows" => [ row ]
          }
        )
      end
    end
  end
end
