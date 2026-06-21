require "test_helper"

module Admin
  class AicooDatahubControllerTest < ActionDispatch::IntegrationTest
    test "shows datahub dashboard" do
      AicooDataSnapshot.create!(source_type: "ga4", source_id: 1, payload: { page_views: 10 })
      AicooDataSnapshot.create!(source_type: "gsc", source_id: 2, payload: { clicks: 3 })
      AicooDataSnapshot.create!(source_type: "landing_page", source_id: 3, payload: { pv: 5 })
      AicooDataSnapshot.create!(source_type: "revenue_execution", source_id: 4, payload: { predicted_value: 10_000 })

      get admin_aicoo_datahub_url

      assert_response :success
      assert_includes response.body, "実績データ"
      assert_includes response.body, "GA4/GSCデータ取込"
      assert_includes response.body, "サイト別分析設定"
      assert_includes response.body, "Analytics取込を再処理"
      assert_not_includes response.body, "Analytics API設定"
      assert_includes response.body, "この画面でやること"
      assert_includes response.body, "PV・CV・収益などの実績データを集め"
      assert_includes response.body, "総実績データ数"
      assert_includes response.body, "今日取得数"
      assert_includes response.body, "GA4"
      assert_includes response.body, "GSC"
      assert_includes response.body, "LP実績データ"
      assert_includes response.body, "収益実績データ"
      assert_includes response.body, "LP実績データ収集"
      assert_includes response.body, "収益実績データ収集"
      assert_includes response.body, "取込データ収集"
      assert_includes response.body, "全データ収集"
      assert_includes response.body, "今すぐ自動収集実行"
      assert_includes response.body, "データ収集履歴"
      assert_includes response.body, "採点候補"
      assert_includes response.body, "最近の実績データ"
    end

    test "shows scoring candidates" do
      experiment = AicooLabExperiment.create!(
        title: "DataHub view scoring lab",
        experiment_type: "lp",
        acquisition_channel: "seo",
        status: "running"
      )
      landing_page = create_landing_page(experiment:)
      AicooDataSnapshot.create!(
        source_type: "landing_page",
        source_id: landing_page.id,
        payload: {
          experiment_id: experiment.id,
          pv: 100,
          cta_click: 10,
          signup: 2
        }
      )

      get admin_aicoo_datahub_url

      assert_response :success
      assert_includes response.body, "DataHub view scoring lab"
      assert_includes response.body, "新規事業検証"
      assert_includes response.body, "使える指標"
      assert_includes response.body, admin_aicoo_lab_scoring_queue_snapshot_path(experiment, 30)
    end

    test "collects landing page snapshots and shows flash" do
      create_landing_page

      assert_difference("AicooDataSnapshot.where(source_type: 'landing_page').count", 1) do
        post admin_aicoo_datahub_collect_landing_pages_url
      end

      assert_redirected_to admin_aicoo_datahub_url
      follow_redirect!
      assert_includes response.body, "LP実績データを1件作成しました"
    end

    test "collects revenue snapshots and shows flash" do
      create_revenue_execution

      assert_difference("AicooDataSnapshot.where(source_type: 'revenue_execution').count", 1) do
        post admin_aicoo_datahub_collect_revenue_url
      end

      assert_redirected_to admin_aicoo_datahub_url
      follow_redirect!
      assert_includes response.body, "収益実績データを1件作成しました"
    end

    test "collects data import snapshots and shows flash" do
      create_data_import(source_type: "ga4", raw_text: JSON.generate(page_views: 10))
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))

      assert_difference("AicooDataSnapshot.count", 2) do
        post admin_aicoo_datahub_collect_data_imports_url
      end

      assert_redirected_to admin_aicoo_datahub_url
      follow_redirect!
      assert_includes response.body, "取込データを2件作成しました"
    end

    test "collects all snapshots and skips same day duplicates" do
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))
      create_landing_page
      create_revenue_execution

      assert_difference("AicooDataSnapshot.count", 3) do
        post admin_aicoo_datahub_collect_all_url
      end
      assert_no_difference("AicooDataSnapshot.count") do
        post admin_aicoo_datahub_collect_all_url
      end

      assert_redirected_to admin_aicoo_datahub_url
      follow_redirect!
      assert_includes response.body, "全実績データを0件作成しました"
    end

    test "runs daily collection and shows flash" do
      create_data_import(source_type: "gsc", raw_text: JSON.generate(rows: [ { clicks: 2, impressions: 10 } ]))
      create_landing_page
      create_revenue_execution

      assert_difference("AicooDataHubCollectionRun.count", 1) do
        assert_difference("AicooDataSnapshot.count", 3) do
          post admin_aicoo_datahub_run_daily_collection_url
        end
      end

      run = AicooDataHubCollectionRun.last
      assert_redirected_to admin_aicoo_datahub_url
      assert_equal "success", run.status
      assert_equal 3, run.snapshot_count
      follow_redirect!
      assert_includes response.body, "自動収集を実行しました。実績データを3件作成しました"
      assert_includes response.body, "success"
    end

    private

    def create_landing_page(experiment: nil)
      experiment ||= AicooLabExperiment.create!(
        title: "DataHub controller LP",
        experiment_type: "lp",
        acquisition_channel: "seo"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "DataHub controller headline",
        subheadline: "DataHub controller subheadline",
        body: "DataHub controller body",
        cta_text: "事前登録する"
      )
    end

    def create_revenue_execution
      AicooRevenueExecution.create!(
        source_type: "candidate",
        source_id: 1,
        title: "DataHub controller revenue",
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
      business = Business.create!(name: "DataHub controller #{source_type}")
      data_source = business.data_sources.create!(name: "DataHub controller #{source_type}", source_type:)
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
