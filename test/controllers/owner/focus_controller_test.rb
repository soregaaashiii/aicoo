require "test_helper"

module Owner
  class FocusControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
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
      assert_not_includes response.body, "Developer Mode"
      assert_not_includes response.body, "運用・実行管理"
      assert_not_includes response.body, "Auto Build"
      assert_not_includes response.body, "Queue"
      assert_not_includes response.body, "Raw Data"
      assert_not_includes response.body, "Prompt一覧"
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

    test "hides incomplete analyzer result from Today" do
      incomplete = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "検索需要があるテーマの記事を1本追加する",
        status: "approved",
        action_type: "seo_article",
        generation_source: "business_analyzer",
        immediate_value_yen: 50_000,
        expected_hours: 1,
        success_probability: 0.7,
        evaluation_reason: "Analyzer intermediate result",
        metadata: {
          "execution_mode" => "content_creation",
          "action_plan" => {
            "target" => "吸えログ 比較",
            "execution_steps" => [ "記事を書く" ],
            "execution_units" => [
              {
                "label" => "検索需要があるテーマの記事を1本追加する",
                "target_amount" => 1,
                "estimated_minutes" => 90
              }
            ]
          }
        }
      )
      concrete = create_today_candidate!(title: "「吸えログ 比較」向けの比較記事を1本作成する")

      get owner_focus_url

      assert_response :success
      assert_includes response.body, concrete.title
      assert_not_includes response.body, incomplete.title
      assert_select "a[href='#{action_workspace_path(incomplete)}']", text: "詳細を見る", count: 0
      assert_equal "abstract_concrete_task", incomplete.reload.metadata.fetch("today_exclusion_reason")
    end

    test "does not show dashboard in sidebar" do
      get owner_focus_url

      assert_response :success
      assert_includes response.body, "CEO MODE"
      assert_includes response.body, "Today"
      assert_includes response.body, "SERP"
      assert_includes response.body, "Business"
      assert_includes response.body, "Overview"
      assert_not_includes response.body, ">Dashboard<"
      assert_not_includes response.body, ">操作盤<"
      assert_not_includes response.body, ">Auto Build<"
      assert_not_includes response.body, ">Learning<"
      assert_not_includes response.body, ">Revenue<"
      assert_not_includes response.body, ">Action Candidates<"
    end

    test "deduplicates repeated stuck daily runs while keeping improvements visible" do
      3.times do |index|
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

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Daily Run 2026-07-10 が business_metrics_import で停止"
      assert_includes response.body, "同一障害 3件"
      assert_equal 1, response.body.scan("Daily Run 2026-07-10 が business_metrics_import で停止").size
      assert_includes response.body, improvement.title
    end

    test "excludes action candidates with external target urls" do
      external = create_today_candidate!(
        title: "外部サイトを改善する",
        metadata: {
          "execution_mode" => "manual_operation",
          "concrete_task" => "外部サイトを改善する",
          "target_url" => "https://it-trend.jp/log_management/article/84-0008",
          "action_plan" => {
            "summary" => "外部サイトを改善する",
            "target" => "https://it-trend.jp/log_management/article/84-0008",
            "owner_next_step" => "外部サイトを見る",
            "execution_steps" => [ "外部サイトを見る" ],
            "execution_units" => [ { "label" => "外部サイトを見る" } ]
          }
        }
      )

      get owner_focus_url

      assert_response :success
      assert_not_includes response.body, "https://it-trend.jp/log_management/article/84-0008"
      assert_equal "external_target_url", external.reload.metadata.fetch("today_exclusion_reason")
    end

    test "does not create fallback Today item for data backed business with no visible candidate" do
      ActionCandidate.delete_all
      business = businesses(:suelog)
      business.business_metric_dailies.where(recorded_on: Date.current).delete_all
      business.business_metric_dailies.create!(
        recorded_on: Date.current,
        impressions: 120,
        clicks: 4,
        sessions: 20,
        pageviews: 35
      )

      assert_no_difference("ActionCandidate.where(business: business, generation_source: 'business_analyzer').count") do
        get owner_focus_url
      end

      assert_response :success
      assert_not_includes response.body, "要具体化"
      assert_not_includes response.body, "#{business.name}の分析データから次のTODOを1件具体化する"
    end

    test "stores exclusion reason when candidate is not eligible for Today" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "自動で実行できるコード改修",
        status: "idea",
        action_type: "ui_improvement",
        generation_source: "business_analyzer",
        immediate_value_yen: 20_000,
        expected_hours: 1,
        success_probability: 0.5,
        evaluation_reason: "Codexで自動実行できるためTodayには出さない",
        metadata: {
          "execution_mode" => "code_revision",
          "concrete_task" => "流入上位ページにCTAを追加する",
          "action_plan" => {
            "summary" => "流入上位ページにCTAを追加する",
            "target" => "流入上位ページ",
            "execution_steps" => [ "CTAを追加する" ],
            "execution_units" => [ { "label" => "CTAを追加する" } ]
          }
        }
      )

      get owner_focus_url

      assert_response :success
      assert_equal "code_revision_auto_executable", candidate.reload.metadata.fetch("today_exclusion_reason")
    end

    test "shows multiple suelog site insight candidates ordered by expected value" do
      high = create_today_candidate!(
        title: "梅田の居酒屋店舗を20件追加する",
        immediate_value_yen: 120_000,
        expected_hours: 5,
        success_probability: 0.55,
        metadata: suelog_metadata("梅田の居酒屋店舗を20件追加する", expected_score: 900)
      )
      middle = create_today_candidate!(
        title: "東通り 居酒屋 喫煙可のtitle/metaを改善する",
        immediate_value_yen: 80_000,
        expected_hours: 1.2,
        success_probability: 0.36,
        metadata: suelog_metadata("東通り 居酒屋 喫煙可のtitle/metaを改善する", expected_score: 650)
      )
      low = create_today_candidate!(
        title: "梅田で喫煙できるバーまとめ記事を作成する",
        immediate_value_yen: 30_000,
        expected_hours: 3,
        success_probability: 0.34,
        metadata: suelog_metadata("梅田で喫煙できるバーまとめ記事を作成する", expected_score: 300)
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, high.title
      assert_includes response.body, middle.title
      assert_includes response.body, low.title
      assert_operator response.body.index(high.title), :<, response.body.index(middle.title)
      assert_operator response.body.index(middle.title), :<, response.body.index(low.title)
    end

    private

    def suelog_metadata(title, expected_score:)
      {
        "suelog_site_insights" => true,
        "execution_mode" => "data_operation",
        "concrete_task" => title,
        "expected_score" => expected_score,
        "roi_score" => expected_score / 2,
        "work_cost" => 5,
        "recommended_action" => "店舗追加優先",
        "action_plan" => {
          "summary" => title,
          "target" => "梅田 / 居酒屋",
          "owner_next_step" => title,
          "execution_steps" => [ title ],
          "execution_units" => [ { "label" => title, "target_amount" => 20 } ]
        },
        "execution_units" => [ { "label" => title, "target_amount" => 20 } ]
      }
    end

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
