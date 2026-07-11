require "test_helper"

module Owner
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
      Business.where(created_by_aicoo: true).update_all(resource_status: "archived")
    end

    test "owner dashboard uses the same TodayActionBoard items as focus" do
      high = create_today_candidate!(
        title: "梅田の未確認店舗を30件確認済みにする",
        immediate_value_yen: 90_000,
        expected_hours: 1.5,
        success_probability: 0.8
      )
      low = create_today_candidate!(
        title: "難波の未確認店舗を10件確認済みにする",
        immediate_value_yen: 10_000,
        expected_hours: 1,
        success_probability: 0.5
      )

      get owner_dashboard_url(mode: "revenue")
      assert_response :success
      dashboard_item_ids = today_item_ids(response.body)

      get owner_focus_url(mode: "revenue")
      assert_response :success
      focus_item_ids = today_item_ids(response.body)

      assert_equal focus_item_ids, dashboard_item_ids
      assert_equal [ "action_candidate:#{high.id}", "action_candidate:#{low.id}" ], dashboard_item_ids
      assert_not_includes response.body, "今日やること TOP10"
    end

    test "owner dashboard shows deduplicated critical issue and improvements in one ranking" do
      2.times do |index|
        run = AicooDailyRun.create!(
          target_date: Date.new(2026, 7, 10),
          status: "stuck",
          source: "cron",
          started_at: (index + 1).hours.ago,
          error_message: "business_metrics_import timeout"
        )
        run.aicoo_daily_run_steps.create!(
          step_name: "business_metrics_import",
          status: "running",
          started_at: run.started_at,
          error_message: "business_metrics_import timeout"
        )
      end
      improvement = create_today_candidate!(title: "梅田の未確認店舗を30件確認済みにする")

      get owner_dashboard_url(mode: "revenue")

      assert_response :success
      assert_includes response.body, "同一障害 2件"
      assert_includes response.body, improvement.title
      ids = today_item_ids(response.body)
      assert_equal 1, ids.count { |id| id.start_with?("daily_run_issue:") }
      assert_includes ids, "action_candidate:#{improvement.id}"
    end

    test "owner dashboard shows twenty actions per page and page two starts at rank twenty one" do
      candidates = 25.times.map do |index|
        create_today_candidate!(
          title: "梅田の確認済み店舗を#{index + 1}件増やす",
          immediate_value_yen: 100_000 - index,
          metadata: today_metadata(
            title: "梅田の確認済み店舗を#{index + 1}件増やす",
            target: "梅田 / 確認済み #{index + 1}"
          )
        )
      end

      get owner_dashboard_url(mode: "revenue")

      assert_response :success
      assert_equal 20, today_item_ids(response.body).size
      assert_equal "action_candidate:#{candidates.first.id}", today_item_ids(response.body).first
      assert_includes response.body, "次ページ"

      get owner_dashboard_url(mode: "revenue", home_actions_page: 2)

      assert_response :success
      assert_equal 5, today_item_ids(response.body).size
      assert_equal "action_candidate:#{candidates[20].id}", today_item_ids(response.body).first
      assert_includes response.body, "<td class=\"number\">21</td>"
    end

    test "owner dashboard pagination uses home_actions_page without changing today_actions_page" do
      25.times do |index|
        create_today_candidate!(
          title: "難波の店舗カードを#{index + 1}件改善する",
          immediate_value_yen: 100_000 - index,
          metadata: today_metadata(
            title: "難波の店舗カードを#{index + 1}件改善する",
            target: "難波 / 店舗カード #{index + 1}"
          )
        )
      end

      get owner_dashboard_url(mode: "revenue", home_actions_page: 2, today_actions_page: 7)

      assert_response :success
      assert_includes response.body, "home_actions_page=1"
      assert_includes response.body, "today_actions_page=7"
    end

    private

    def create_today_candidate!(attributes = {})
      title = attributes.fetch(:title, "梅田の未確認店舗を30件確認済みにする")
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          title:,
          status: "approved",
          action_type: "seo_improvement",
          generation_source: "business_analyzer",
          immediate_value_yen: 50_000,
          expected_hours: 1,
          success_probability: 0.7,
          evaluation_reason: "流入上位ページの確認済み率が低いため。",
          metadata: {
            "execution_mode" => "manual_operation",
            "concrete_task" => title,
            "action_plan" => {
              "summary" => title,
              "target" => "梅田 / 未確認店舗",
              "owner_next_step" => "対象店舗リストを開く",
              "execution_steps" => [ "対象店舗リストを開く", "確認済みに更新する" ],
              "execution_units" => [
                {
                  "label" => title,
                  "area" => "梅田",
                  "target_amount" => 30,
                  "estimated_minutes" => 90
                }
              ]
            },
            "execution_units" => [
              {
                "label" => title,
                "area" => "梅田",
                "target_amount" => 30,
                "estimated_minutes" => 90
              }
            ]
          }
        }.merge(attributes)
      )
    end

    def today_metadata(title:, target: "梅田 / 未確認店舗")
      {
        "execution_mode" => "manual_operation",
        "concrete_task" => title,
        "action_plan" => {
          "summary" => title,
          "target" => target,
          "target_url_or_identifier" => target,
          "owner_next_step" => "対象を開く",
          "execution_steps" => [ "対象を開く" ],
          "execution_units" => [ { "label" => title } ]
        },
        "execution_units" => [ { "label" => title } ]
      }
    end

    def today_item_ids(body)
      body.scan(/data-today-item-id="([^"]+)"/).flatten
    end
  end
end
