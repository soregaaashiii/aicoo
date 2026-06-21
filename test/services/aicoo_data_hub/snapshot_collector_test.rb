require "test_helper"

module AicooDataHub
  class SnapshotCollectorTest < ActiveSupport::TestCase
    test "collects gsc data import snapshot" do
      site = AicooAnalyticsSite.create!(name: "吸えログ", domain: "suelog.jp", gsc_site_url: "sc-domain:suelog.jp")
      data_import = create_data_import(
        source_type: "gsc",
        raw_text: JSON.generate(
          rows: [
            { clicks: 10, impressions: 100, ctr: 0.1, position: 3.2 },
            { clicks: 5, impressions: 50, ctr: 0.1, position: 4.8 }
          ]
        )
      )
      data_import.update!(aicoo_analytics_site: site)

      assert_difference("AicooDataSnapshot.where(source_type: 'gsc').count", 1) do
        SnapshotCollector.new.collect_gsc
      end

      snapshot = AicooDataSnapshot.last
      assert_equal data_import.id, snapshot.source_id
      assert_equal 15, snapshot.payload.dig("metrics", "clicks")
      assert_equal 150, snapshot.payload.dig("metrics", "impressions")
      assert_equal 0.1, snapshot.payload.dig("metrics", "ctr")
      assert_equal 4.0, snapshot.payload.dig("metrics", "position")
      assert_equal site.id, snapshot.payload["analytics_site_id"]
      assert_equal "吸えログ", snapshot.payload["site_name"]
      assert_equal "suelog.jp", snapshot.payload["domain"]
      assert_equal "gsc", snapshot.payload["source_type"]
      assert_equal 2, snapshot.payload["rows"].size
    end

    test "collects ga4 data import snapshot" do
      data_import = create_data_import(
        source_type: "ga4",
        raw_text: JSON.generate(page_views: 120, users: 80, sessions: 90)
      )

      assert_difference("AicooDataSnapshot.where(source_type: 'ga4').count", 1) do
        SnapshotCollector.new.collect_ga4
      end

      snapshot = AicooDataSnapshot.last
      assert_equal data_import.id, snapshot.source_id
      assert_equal 120, snapshot.payload.dig("metrics", "page_views")
      assert_equal 80, snapshot.payload.dig("metrics", "users")
      assert_equal 90, snapshot.payload.dig("metrics", "sessions")
    end

    test "collects landing page metrics" do
      landing_page = create_landing_page
      3.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }
      landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")
      landing_page.aicoo_lab_signups.create!(email: "datahub@example.com")

      assert_difference("AicooDataSnapshot.where(source_type: 'landing_page').count", 1) do
        SnapshotCollector.new.collect_landing_pages
      end

      snapshot = AicooDataSnapshot.last
      assert_equal landing_page.id, snapshot.source_id
      assert_equal 3, snapshot.payload["pv"]
      assert_equal 1, snapshot.payload["cta_click"]
      assert_equal 1, snapshot.payload["signup"]
      assert_in_delta 0.333, snapshot.payload["cta_rate"].to_f, 0.001
    end

    test "collects revenue execution metrics" do
      execution = AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: 1,
        title: "DataHub revenue",
        expected_90d_profit_yen: 50_000,
        success_probability: 0.2,
        revenue_total_value_yen: 10_000,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "done",
        actual_90d_profit_yen: 8_000
      )

      assert_difference("AicooDataSnapshot.where(source_type: 'revenue_execution').count", 1) do
        SnapshotCollector.new.collect_revenue
      end

      snapshot = AicooDataSnapshot.last
      assert_equal execution.id, snapshot.source_id
      assert_equal 10_000, snapshot.payload["predicted_value"]
      assert_equal 8_000, snapshot.payload["actual_90d_profit_yen"]
      assert_equal 80.0, snapshot.payload["calibration_score"]
    end

    test "collects data imports for ga4 and gsc" do
      create_data_import(source_type: "ga4", raw_text: JSON.generate(page_views: 10))
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))

      result = nil
      assert_difference("AicooDataSnapshot.count", 2) do
        result = SnapshotCollector.new.collect_data_imports
      end

      assert_equal 2, result.count
      assert_equal 1, AicooDataSnapshot.where(source_type: "ga4").count
      assert_equal 1, AicooDataSnapshot.where(source_type: "gsc").count
    end

    test "collects all sources" do
      create_data_import(source_type: "ga4", raw_text: JSON.generate(page_views: 10))
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))
      create_landing_page
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: 1,
        title: "DataHub all revenue",
        expected_90d_profit_yen: 50_000,
        success_probability: 0.2,
        revenue_total_value_yen: 10_000,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "planned"
      )

      result = nil
      assert_difference("AicooDataSnapshot.count", 4) do
        result = SnapshotCollector.new.collect_all
      end

      assert_equal 4, result.count
      assert_equal %w[ga4 gsc landing_page revenue_execution], AicooDataSnapshot.order(:source_type).pluck(:source_type)
    end

    test "does not create duplicate snapshots on the same day" do
      landing_page = create_landing_page

      assert_difference("AicooDataSnapshot.where(source_type: 'landing_page').count", 1) do
        SnapshotCollector.new.collect_landing_pages
      end
      assert_no_difference("AicooDataSnapshot.where(source_type: 'landing_page').count") do
        result = SnapshotCollector.new.collect_landing_pages
        assert_equal 0, result.count
      end

      assert_equal landing_page.id, AicooDataSnapshot.find_by(source_type: "landing_page").source_id
    end

    private

    def create_data_import(source_type:, raw_text:)
      business = Business.create!(name: "DataHub #{source_type}")
      data_source = business.data_sources.create!(name: "DataHub #{source_type}", source_type:)
      data_source.data_imports.create!(
        filename: "#{source_type}.json",
        content_type: "application/json",
        row_count: 2,
        raw_text:,
        processed_text: "processed",
        imported_at: Time.current
      )
    end

    def create_landing_page
      experiment = AicooLabExperiment.create!(
        title: "DataHub LP",
        experiment_type: "lp",
        acquisition_channel: "seo"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "DataHub headline",
        subheadline: "DataHub subheadline",
        body: "DataHub body",
        cta_text: "事前登録する"
      )
    end
  end
end
