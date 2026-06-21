require "test_helper"

module Admin
  class AnalyticsImportsControllerTest < ActionDispatch::IntegrationTest
    test "shows analytics import page and recent imports" do
      data_import = create_data_import(source_type: "ga4", filename: "recent-ga4.csv", raw_text: ga4_csv)

      get admin_analytics_imports_url

      assert_response :success
      assert_includes response.body, "GA4/GSCデータ取込"
      assert_includes response.body, "GA4データ貼り付け"
      assert_includes response.body, "保存後にDataHub収集とRevenue推定を更新する"
      assert_includes response.body, "再処理"
      assert_includes response.body, data_import.filename
      assert_includes response.body, "GA4"
    end

    test "creates ga4 data import from pasted text" do
      assert_difference("DataSource.where(source_type: 'ga4').count", 1) do
        assert_difference("DataImport.count", 1) do
          post admin_analytics_imports_url, params: {
            analytics_import: {
              source_type: "ga4",
              filename: "ga4-paste.csv",
              raw_text: ga4_csv
            }
          }
        end
      end

      data_import = DataImport.last
      assert_redirected_to admin_analytics_imports_url
      assert_equal "ga4", data_import.data_source.source_type
      assert_equal "ga4-paste.csv", data_import.filename
      assert_equal "text/csv", data_import.content_type
      assert_equal 2, data_import.row_count
      assert data_import.imported_at.present?
    end

    test "creates gsc data import from pasted text" do
      assert_difference("DataSource.where(source_type: 'gsc').count", 1) do
        assert_difference("DataImport.count", 1) do
          post admin_analytics_imports_url, params: {
            analytics_import: {
              source_type: "gsc",
              filename: "gsc-paste.csv",
              raw_text: gsc_csv
            }
          }
        end
      end

      data_import = DataImport.last
      assert_redirected_to admin_analytics_imports_url
      assert_equal "gsc", data_import.data_source.source_type
      assert_equal "gsc-paste.csv", data_import.filename
      assert_equal 2, data_import.row_count
    end

    test "datahub can create snapshots from analytics imports" do
      create_data_import(source_type: "ga4", filename: "ga4-snapshot.csv", raw_text: ga4_csv)
      create_data_import(source_type: "gsc", filename: "gsc-snapshot.csv", raw_text: gsc_csv)

      assert_difference("AicooDataSnapshot.count", 2) do
        result = AicooDataHub::SnapshotCollector.new.collect_data_imports
        assert_equal 2, result.count
      end

      ga4_snapshot = AicooDataSnapshot.find_by!(source_type: "ga4")
      gsc_snapshot = AicooDataSnapshot.find_by!(source_type: "gsc")
      assert_equal 120, ga4_snapshot.payload.dig("metrics", "page_views")
      assert_equal 40, ga4_snapshot.payload.dig("metrics", "users")
      assert_equal 5, gsc_snapshot.payload.dig("metrics", "clicks")
      assert_equal 100, gsc_snapshot.payload.dig("metrics", "impressions")
    end

    test "checked option creates snapshot and updates neglect loss estimates" do
      action = create_stale_action_candidate

      assert_difference("DataImport.count", 1) do
        assert_difference("AicooDataSnapshot.where(source_type: 'gsc').count", 1) do
          post admin_analytics_imports_url, params: {
            analytics_import: {
              source_type: "gsc",
              filename: "gsc-pipeline.csv",
              raw_text: gsc_csv,
              run_after_import: "1"
            }
          }
        end
      end

      assert_redirected_to admin_analytics_imports_url
      follow_redirect!
      assert_includes response.body, "Snapshot 1件作成"
      assert_includes response.body, "放置損失推定 1件更新"
      assert_operator action.reload.estimated_neglect_loss_90d_yen, :>, 0
    end

    test "unchecked option only saves data import" do
      create_stale_action_candidate

      assert_difference("DataImport.count", 1) do
        assert_no_difference("AicooDataSnapshot.count") do
          post admin_analytics_imports_url, params: {
            analytics_import: {
              source_type: "ga4",
              filename: "ga4-save-only.csv",
              raw_text: ga4_csv,
              run_after_import: "0"
            }
          }
        end
      end

      assert_redirected_to admin_analytics_imports_url
      follow_redirect!
      assert_includes response.body, "GA4データを保存しました"
      assert_no_match(/Snapshot \d+件作成/, response.body)
    end

    test "reprocess runs snapshot collection and neglect loss estimation" do
      action = create_stale_action_candidate
      data_import = create_data_import(source_type: "gsc", filename: "gsc-reprocess.csv", raw_text: gsc_csv)

      assert_difference("AicooDataSnapshot.where(source_type: 'gsc').count", 1) do
        post reprocess_admin_analytics_import_url(data_import)
      end

      assert_redirected_to admin_analytics_imports_url
      follow_redirect!
      assert_includes response.body, "再処理しました"
      assert_includes response.body, "Snapshot 1件作成"
      assert_includes response.body, "放置損失推定 1件更新"
      assert_operator action.reload.estimated_neglect_loss_90d_yen, :>, 0
    end

    private

    def create_data_import(source_type:, filename:, raw_text:)
      business = Business.create!(name: "Analytics import #{source_type} #{SecureRandom.hex(4)}")
      data_source = business.data_sources.create!(name: "#{source_type.upcase} source", source_type:)
      data_source.data_imports.create!(
        filename:,
        content_type: "text/csv",
        row_count: raw_text.lines.count,
        raw_text:,
        imported_at: Time.current
      )
    end

    def ga4_csv
      "page_views,users,sessions\n120,40,55\n"
    end

    def gsc_csv
      "query,clicks,impressions,position\nsmoking cafe,5,100,8.5\n"
    end

    def create_stale_action_candidate
      business = Business.create!(name: "Analytics stale action #{SecureRandom.hex(4)}")
      action = business.action_candidates.create!(
        title: "Analytics stale revenue action",
        immediate_value_yen: 90_000,
        success_probability: 0.5,
        expected_hours: 2,
        cost_yen: 0
      )
      action.update_columns(updated_at: 45.days.ago)
      action
    end
  end
end
