require "test_helper"

module Aicoo
  module LpIntegration
    class LandingPageAnalyzerTest < ActiveSupport::TestCase
      setup do
        @business = Business.create!(name: "LP Analyzer test", status: "launched", business_type: "landing_page")
        @campaign = @business.business_campaigns.create!(name: "SEO", campaign_type: "seo")
        @landing_page = LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "Analyzer LP",
          source_type: "public_url",
          url: "https://lp.example.com/analyzer",
          ga4_page_path: "/analyzer",
          public_status: "published"
        )
        @landing_page.update!(metadata: @landing_page.metadata.to_h.merge(
          "cloudflare_url" => "https://aicoo-lp.pages.dev/analyzer/",
          "cloudflare_deploy_status" => "deployed",
          "last_published_at" => 20.days.ago.iso8601,
          "expected_profit_yen" => 50_000
        ))
      end

      test "builds one factual lp payload from ga4 gsc activity cloudflare and revenue" do
        snapshots = metric_snapshots(
          ga4_rows: [
            ga4_row("/analyzer", 2.days.ago, sessions: 100, users: 80, conversions: 5, pageviews: 130, event_count: 210)
              .merge("scrolls" => 65, "bounce_rate" => 0.35)
          ],
          gsc_rows: [
            gsc_row("https://lp.example.com/analyzer", 2.days.ago, query: "LP analyzer", impressions: 500, clicks: 50, position: 8)
          ]
        )
        activity = BusinessActivityLog.new(
          business: @business,
          activity_type: "inquiry_created",
          resource_type: "BusinessPrototype",
          resource_id: @landing_page.id.to_s,
          occurred_at: 1.day.ago
        )
        candidate = @business.action_candidates.create!(
          title: "Analyzer LPを改善",
          action_type: "ui_improvement",
          generation_source: "lp_learning",
          metadata: { "landing_page_id" => @landing_page.id },
          immediate_value_yen: 50_000,
          success_probability: 1
        )
        revenue = RevenueEvent.new(
          business: @business,
          action_candidate: candidate,
          event_type: "revenue",
          amount: 30_000,
          occurred_on: Date.yesterday
        )

        payload = LandingPageAnalyzer.new(
          business: @business,
          landing_page: @landing_page,
          snapshots:,
          activity_logs: [ activity ],
          revenue_events: [ revenue ]
        ).call.payload

        assert_equal "business_prototype_landing_page_analytics", payload["record_type"]
        assert_equal 100, payload.dig("ga4", "sessions")
        assert_equal 80, payload.dig("ga4", "users")
        assert_equal 0.05, payload.dig("ga4", "conversion_rate")
        assert_equal 0.5, payload.dig("ga4", "scroll_rate")
        assert_equal 1, payload.dig("gsc", "query_count")
        assert_equal "LP analyzer", payload.dig("gsc", "queries", 0, "query")
        assert_equal 1, payload.dig("activity", "inquiries")
        assert_equal 30_000, payload.dig("evaluation", "actual_profit_yen")
        assert_equal 50_000, payload.dig("evaluation", "expected_profit_yen")
        assert_equal "https://aicoo-lp.pages.dev/analyzer/", payload.dig("cloudflare", "public_url")
        assert_equal "mvp_planner", payload.dig("learning", "future_consumer") if payload["learning"]
      end

      test "stores a seven day before and after learning result for a completed b variant" do
        source = @landing_page
        variant = LandingPageRegistry.new(business: @business).save!(
          campaign_id: @campaign.id,
          name: "Analyzer LP B",
          source_type: "public_url",
          url: "https://lp.example.com/analyzer-b",
          ga4_page_path: "/analyzer-b",
          public_status: "published"
        )
        candidate = @business.action_candidates.create!(
          title: "CTAを改善",
          action_type: "ui_improvement",
          generation_source: "lp_learning",
          immediate_value_yen: 20_000,
          success_probability: 0.5,
          metadata: {
            "landing_page_id" => source.id,
            "lp_expected_value" => { "type" => "cta_improvement", "target_metric" => "conversion_rate" }
          }
        )
        task = @business.auto_revision_tasks.create!(
          action_candidate: candidate,
          title: "B Variant",
          status: "completed",
          risk_level: "medium",
          priority_score: 20_000,
          metadata: {
            "workflow_type" => "external_lp_improvement",
            "source_landing_page_prototype_id" => source.id,
            "landing_page_prototype_id" => variant.id
          }
        )
        task.update_columns(finished_at: 8.days.ago, updated_at: 8.days.ago)
        variant.update!(metadata: variant.metadata.to_h.merge(
          "cloudflare_url" => "https://aicoo-lp.pages.dev/analyzer-b/",
          "cloudflare_deploy_status" => "deployed",
          "last_published_at" => 8.days.ago.iso8601,
          "ab_source_landing_page_id" => source.id
        ))
        snapshots = metric_snapshots(
          ga4_rows: [
            ga4_row("/analyzer", 10.days.ago, sessions: 100, users: 70, conversions: 1, pageviews: 120, event_count: 150),
            ga4_row("/analyzer-b", 3.days.ago, sessions: 100, users: 75, conversions: 5, pageviews: 125, event_count: 180)
          ],
          gsc_rows: []
        )

        learning = LandingPageLearningBuilder.new(
          business: @business,
          landing_page: variant,
          snapshots:
        ).call

        assert_equal "evaluated", learning["status"]
        assert_equal source.id, learning["source_landing_page_id"]
        assert_equal variant.id, learning["landing_page_id"]
        assert_equal 0.01, learning.dig("before", "conversion_rate")
        assert_equal 0.05, learning.dig("after", "conversion_rate")
        assert_equal 0.04, learning.dig("deltas", "conversion_rate", "delta")
        assert_equal true, learning["success"]
        assert_includes learning["learning_scope"], "global"
      end

      test "data hub stores one external lp analytics snapshot per day" do
        assert_difference -> { AicooDataSnapshot.where(source_type: "landing_page_analytics", source_id: @landing_page.id).count }, 1 do
          result = AicooDataHub::SnapshotCollector.new.collect_external_landing_page_analytics
          assert_equal 1, result.created_count
        end

        assert_no_difference -> { AicooDataSnapshot.where(source_type: "landing_page_analytics", source_id: @landing_page.id).count } do
          result = AicooDataHub::SnapshotCollector.new.collect_external_landing_page_analytics
          assert_equal 0, result.created_count
        end
      end

      private

      def metric_snapshots(ga4_rows:, gsc_rows:)
        { "ga4" => create_snapshot("ga4", ga4_rows), "gsc" => create_snapshot("gsc", gsc_rows) }
      end

      def create_snapshot(source_type, rows)
        source = @business.data_sources.create!(name: "#{source_type} #{SecureRandom.hex(3)}", source_type:, status: "active")
        data_import = source.data_imports.create!(
          filename: "#{source_type}.json",
          content_type: "application/json",
          raw_text: { "rows" => rows }.to_json,
          row_count: rows.size,
          imported_at: Time.current
        )
        AicooDataSnapshot.create!(
          source_type:,
          source_id: data_import.id,
          captured_at: Time.current,
          payload: { "business_id" => @business.id, "rows" => rows }
        )
      end

      def ga4_row(path, date, sessions:, users:, conversions:, pageviews:, event_count:)
        {
          "date" => date.to_date.iso8601,
          "pagePath" => path,
          "screenPageViews" => pageviews,
          "activeUsers" => users,
          "sessions" => sessions,
          "eventCount" => event_count,
          "keyEvents" => conversions
        }
      end

      def gsc_row(url, date, query:, impressions:, clicks:, position:)
        {
          "date" => date.to_date.iso8601,
          "page" => url,
          "query" => query,
          "impressions" => impressions,
          "clicks" => clicks,
          "position" => position
        }
      end
    end
  end
end
