require "test_helper"

module Owner
  class FocusControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
    end

    test "shows Today as ranking list without hero card" do
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

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Today"
      assert_includes response.body, "収益優先"
      assert_includes response.body, "学習優先"
      assert_includes response.body, "バランス"
      assert_includes response.body, "今日処理するAction"
      assert_includes response.body, "期待利益"
      assert_includes response.body, "想定時間"
      assert_includes response.body, "期待時給"
      assert_includes response.body, "成功率"
      assert_includes response.body, "実行方法"
      assert_includes response.body, high.title
      assert_includes response.body, low.title
      assert_operator response.body.index(high.title), :<, response.body.index(low.title)
      assert_not_includes response.body, "aicoo-decision-hero"
      assert_not_includes response.body, "今日すぐ実行すべき改善はありません。"
    end

    test "ranking tabs keep user on Today page" do
      get owner_focus_url(mode: "learning")

      assert_response :success
      assert_select "a[href='#{owner_focus_path(mode: "revenue")}']", text: "収益優先"
      assert_select "a[href='#{owner_focus_path(mode: "learning")}']", text: "学習優先"
      assert_select "a[href='#{owner_focus_path(mode: "balanced")}']", text: "バランス"
    end

    test "detail links open action workspace instead of business detail" do
      candidate = create_today_candidate!(title: "流入上位5記事に店舗リンクを25件追加する")

      get owner_focus_url

      assert_response :success
      assert_select "a[href='#{action_workspace_path(candidate)}']", text: "詳細を見る"
      today_section = response.body.split("<details class=\"aicoo-developer-mode\"").first
      assert_not_includes today_section, "href=\"#{business_path(candidate.business)}\""
    end

    test "does not show dashboard in sidebar" do
      get owner_focus_url

      assert_response :success
      assert_includes response.body, "CEO MODE"
      assert_includes response.body, "Today"
      assert_not_includes response.body, ">Dashboard<"
      assert_not_includes response.body, ">操作盤<"
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
  end
end
