require "test_helper"

module Admin
  class ExploreImportsControllerTest < ActionDispatch::IntegrationTest
    test "shows import form" do
      get admin_explore_import_url

      assert_response :success
      assert_includes response.body, "Explore Manual Import"
      assert_includes response.body, "Preview"
      assert_includes response.body, "Import"
      assert_includes response.body, "貼り付けテンプレート"
      assert_includes response.body, "title,description,score,observation_type"
      assert_includes response.body, "CSVヘッダーをコピー"
    end

    test "shows source specific import templates" do
      get admin_explore_import_url

      assert_response :success
      assert_includes response.body, "Google Trends"
      assert_includes response.body, "シーシャ 大阪"
      assert_includes response.body, "Reddit"
      assert_includes response.body, "大阪で喫煙できる店が探しにくい"
      assert_includes response.body, "YouTube"
      assert_includes response.body, "シーシャ初心者向け動画が伸びている"
      assert_includes response.body, "X"
      assert_includes response.body, "梅田 喫煙所 投稿増加"
      assert_includes response.body, "Clarity"
      assert_includes response.body, "店舗詳細ページで地図クリック前に離脱"
      assert_includes response.body, "Google Business Profile"
      assert_includes response.body, "電話数が増加"
      assert_includes response.body, "score未入力は50"
      assert_includes response.body, "score 80以上はOwner Taskに乗る可能性があります"
    end

    test "previews pasted text without importing" do
      assert_no_difference("ExploreObservation.count") do
        post admin_explore_import_preview_url, params: {
          explore_import: {
            source_type: "google_trends",
            import_format: "text",
            raw_text: "シーシャ需要増加"
          }
        }
      end

      assert_response :success
      assert_includes response.body, "シーシャ需要増加"
      assert_includes response.body, "生成予定"
      assert_includes response.body, "score未入力は50、observation_type未入力はopportunity"
      assert_includes response.body, "Owner Task Inbox"
    end

    test "imports pasted csv and redirects to explore dashboard" do
      assert_difference("ExploreObservation.count", 1) do
        assert_difference("ExploreImportLog.count", 1) do
          assert_difference("OpportunityDiscoveryItem.count", 1) do
            post admin_explore_import_url, params: {
              explore_import: {
                source_type: "google_trends",
                import_format: "csv",
                raw_text: "title,description,score\nシーシャ需要増加,検索量増加,80"
              }
            }
          end
        end
      end

      assert_redirected_to admin_explore_url
      assert_equal "シーシャ需要増加", ExploreObservation.last.title
      assert_equal "pending", OpportunityDiscoveryItem.last.status
    end
  end
end
