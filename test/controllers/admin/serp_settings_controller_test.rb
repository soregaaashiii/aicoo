require "test_helper"

module Admin
  class SerpSettingsControllerTest < ActionDispatch::IntegrationTest
    test "shows new business exploration screen without business selection" do
      get admin_serp_settings_url

      assert_response :success
      assert_includes response.body, "新規事業探索"
      assert_includes response.body, "探索方法"
      assert_includes response.body, "対象地域"
      assert_includes response.body, "地域指定"
      assert_includes response.body, "1日の探索件数"
      assert_includes response.body, "学習"
      assert_includes response.body, "新しい分野を探す割合"
      assert_includes response.body, "実績のある分野を深掘りする割合"
      assert_includes response.body, "既存事業"
      assert_includes response.body, "削除済み事業"
      assert_includes response.body, "重複市場"
      assert_includes response.body, "今回の走査結果"
      assert_includes response.body, "事業化した一覧"
      assert_not_includes response.body, "対象Business"
      assert_not_includes response.body, "全Business"
      assert_not_includes response.body, "選択中Business"
      assert_not_includes response.body, "Businessごとの"
      assert_not_includes response.body, "name=\"business_id\""
      assert_not_select "select[name='business_id']"
      assert_not_select "input[name='business_id']"
    end

    test "saves exploration settings without business id" do
      patch update_scheduler_admin_serp_settings_url, params: {
        serp_exploration: {
          mode: "industry",
          query: "士業 顧客管理",
          country: "日本",
          region: "大阪",
          daily_query_limit: "12",
          learning_enabled: "0",
          new_field_ratio: "60",
          proven_field_ratio: "40",
          exclusion_rules: %w[existing_businesses deleted_businesses duplicate_markets]
        }
      }

      assert_redirected_to admin_serp_settings_url(anchor: "serp-settings")
      settings = Aicoo::Serp::Scheduler.settings
      assert_equal "industry", settings["exploration_mode"]
      assert_equal "士業 顧客管理", settings["exploration_query"]
      assert_equal "大阪", settings["exploration_region"]
      assert_equal 12, settings["daily_query_limit"]
      assert_equal false, ActiveModel::Type::Boolean.new.cast(settings["learning_enabled"])
      assert_equal 60, settings["new_field_ratio"]
      assert_equal 40, settings["proven_field_ratio"]
    end

    test "old business scoped serp routes are removed" do
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/serp_settings/businesses/#{businesses(:suelog).id}/scan", method: :post)
      end
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/serp_settings/businesses/#{businesses(:suelog).id}/keywords", method: :post)
      end
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/admin/serp_settings/businesses/#{businesses(:suelog).id}/approve_pending", method: :post)
      end
    end

    test "screen can start exploration without any real business" do
      Business.real_businesses.find_each { |business| business.update!(resource_status: "deleted", deleted_at: Time.current) }

      get admin_serp_settings_url

      assert_response :success
      assert_includes response.body, "新規事業探索を実行"
      assert_not_select "select[name='business_id']"
      assert_not_select "input[name='business_id']"
    end
  end
end
