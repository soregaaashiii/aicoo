require "test_helper"

module Aicoo
  module Lovable
    class LandingPageImprovementAnalyzerTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(
          name: "Lovable Learning Test",
          status: "launched",
          lifecycle_stage: "production",
          business_type: "landing_page",
          category: "test"
        )
        experiment = AicooLabExperiment.create!(
          title: "Lovable Learning Test LP",
          experiment_type: "lp",
          acquisition_channel: "direct",
          status: "running",
          approval_status: "approved",
          expected_90d_profit_yen: 0,
          success_probability: 0,
          budget_yen: 0,
          estimated_work_minutes: 0,
          created_by: "test"
        )
        @landing_page = experiment.create_aicoo_lab_landing_page!(
          business: @business,
          headline: "Learning Test",
          cta_text: "問い合わせる",
          status: "published",
          public_status: "published",
          generation_source: "lovable"
        )
        @previous = published_run(
          version: 1,
          published_at: 14.days.ago,
          learning: learning(pageviews: 100, cta_rate: 0.20, cvr: 0.05, roi: 2.0, confidence: 0.75)
        )
        @current = published_run(version: 2, published_at: 3.days.ago)
      end

      test "generates a normal LP learning candidate from a measured performance gap" do
        record_events(views: 100, cta_clicks: 5)

        assert_difference -> { @business.action_candidates.where(generation_source: "lp_learning").count }, 1 do
          result = LandingPageImprovementAnalyzer.new(business: @business, generation_run: @current).call
          assert_equal "improvement_found", result.analysis_status
        end

        candidate = @business.action_candidates.where(generation_source: "lp_learning").last
        assert_equal "proposal", candidate.status
        assert_equal "ui_improvement", candidate.action_type
        assert_equal "lovable_revision", candidate.metadata["execution_mode"]
        assert_equal false, candidate.metadata["codex_eligible"]
        assert_equal 2, candidate.metadata["current_version"]
        assert_equal @current.id, candidate.metadata["learning_id"]
        assert_includes candidate.metadata["lovable_change_request"], "その他の構成・計測・レスポンシブ動作は維持"
      end

      test "does not duplicate a candidate for the same version and improvement" do
        record_events(views: 100, cta_clicks: 5)

        first = LandingPageImprovementAnalyzer.new(business: @business, generation_run: @current).call
        assert_no_difference -> { @business.action_candidates.where(generation_source: "lp_learning").count } do
          second = LandingPageImprovementAnalyzer.new(business: @business, generation_run: @current).call
          assert_operator second.duplicate_count, :>, 0
        end
        assert_equal first.candidates.first.id, @business.action_candidates.where(generation_source: "lp_learning").first.id
      end

      test "keeps collecting without a candidate below the minimum sample" do
        record_events(views: LandingPageLearningComparison::MIN_PAGEVIEWS - 1, cta_clicks: 1)

        assert_no_difference -> { @business.action_candidates.where(generation_source: "lp_learning").count } do
          result = LandingPageImprovementAnalyzer.new(business: @business, generation_run: @current).call
          assert_equal "collecting", result.analysis_status
          assert_equal "insufficient_pageviews", result.skip_reason
        end
      end

      test "selects the strongest measured version as best version" do
        record_events(views: 100, cta_clicks: 5)

        comparison = LandingPageLearningComparison.new(business: @business).call

        assert_equal @previous.id, comparison.best.run.id
        assert_equal "own_versions", comparison.benchmark_source
      end

      test "uses landing page matched GA4 and GSC snapshot rows" do
        create_metric_snapshot("ga4", {
          "date" => Date.current.strftime("%Y%m%d"),
          "pagePath" => "/lp",
          "screenPageViews" => 120,
          "activeUsers" => 80,
          "sessions" => 90,
          "eventCount" => 240,
          "userEngagementDuration" => 4_500,
          "bounceRate" => 0.4
        })
        create_metric_snapshot("gsc", {
          "date" => Date.current.iso8601,
          "page" => "https://example.test/lp",
          "impressions" => 400,
          "clicks" => 24,
          "position" => 9.5
        })

        summary = LearningSummary.new(business: @business, generation_run: @current).call

        assert_equal true, summary.dig("ga4", "available")
        assert_equal "landing_page", summary.dig("ga4", "scope")
        assert_equal 120, summary.dig("ga4", "pageviews")
        assert_equal true, summary.dig("gsc", "available")
        assert_equal 400, summary.dig("gsc", "impressions")
      end

      test "refreshes learning at view milestones even when no CTA is clicked" do
        calls = 0
        LearningRefresher.stub(:call, ->(_landing_page) { calls += 1 }) do
          20.times { @landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
          assert_equal 1, calls

          30.times { @landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
          assert_equal 2, calls
        end
      end

      private

      def published_run(version:, published_at:, learning: nil)
        AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "succeeded",
          prompt: "LP v#{version}",
          generated_count: 1,
          started_at: published_at,
          finished_at: published_at,
          metadata: {
            "pipeline" => "lovable",
            "business_id" => @business.id,
            "landing_page_id" => @landing_page.id,
            "version" => version,
            "version_label" => "v#{version}",
            "request_type" => version == 1 ? "create" : "revision",
            "publication" => {
              "published" => true,
              "published_at" => published_at.iso8601,
              "production_url" => "https://example.test/lp"
            },
            "learning" => learning
          }.compact
        )
      end

      def learning(pageviews:, cta_rate:, cvr:, roi:, confidence:)
        {
          "pageviews" => pageviews,
          "cta_rate" => cta_rate,
          "cvr" => cvr,
          "form_submit_rate" => cvr / cta_rate,
          "scroll_rate" => 0.6,
          "roi" => roi,
          "confidence" => confidence,
          "ga4" => { "bounce_rate" => 0.35, "engagement_seconds" => 80 },
          "metrics" => { "gsc_clicks_per_day" => 10, "gsc_impressions_per_day" => 100 }
        }
      end

      def record_events(views:, cta_clicks:)
        now = Time.current
        rows = Array.new(views) { event_attributes("view", now) } +
          Array.new(cta_clicks) { event_attributes("cta_click", now) }
        AicooLabLandingPageEvent.insert_all!(rows)
      end

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

      def event_attributes(event_type, now)
        {
          aicoo_lab_landing_page_id: @landing_page.id,
          event_type:,
          occurred_at: now,
          metadata: {},
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
