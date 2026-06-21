require "test_helper"

module AicooDataHub
  class DailyCollectorTest < ActiveSupport::TestCase
    test "creates collection run with snapshot count" do
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))
      create_landing_page
      create_revenue_execution

      run = nil
      assert_difference("AicooDataHubCollectionRun.count", 1) do
        assert_difference("AicooDataSnapshot.count", 3) do
          run = DailyCollector.new.call
        end
      end

      assert_equal "success", run.status
      assert_not_nil run.started_at
      assert_not_nil run.finished_at
      assert_equal 3, run.snapshot_count
    end

    private

    def create_landing_page
      experiment = AicooLabExperiment.create!(
        title: "Daily collector LP",
        experiment_type: "lp",
        acquisition_channel: "seo"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "Daily collector headline",
        subheadline: "Daily collector subheadline",
        body: "Daily collector body",
        cta_text: "事前登録する"
      )
    end

    def create_revenue_execution
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: 1,
        title: "Daily collector revenue",
        expected_90d_profit_yen: 50_000,
        success_probability: 0.2,
        revenue_total_value_yen: 10_000,
        estimated_work_minutes: 60,
        budget_yen: 0,
        revenue_score: 10,
        status: "planned"
      )
    end

    def create_data_import(source_type:, raw_text:)
      business = Business.create!(name: "Daily collector #{source_type}")
      data_source = business.data_sources.create!(name: "Daily collector #{source_type}", source_type:)
      data_source.data_imports.create!(
        filename: "#{source_type}.json",
        content_type: "application/json",
        row_count: 1,
        raw_text:,
        imported_at: Time.current
      )
    end
  end
end
