require "test_helper"

module Owner
  class FocusControllerTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
    end

    test "shows business improvement ranking instead of system operations" do
      candidate = create_candidate!(
        title: "CTRが低い記事5本のSEOタイトルを改訂する",
        immediate_value_yen: 40_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "今日の事業改善"
      assert_not_includes response.body, "今日の1件"
      assert_includes response.body, "今日おすすめの事業改善 TOP10"
      assert_includes response.body, "Businessカード"
      assert_includes response.body, businesses(:suelog).name
      assert_includes response.body, candidate.title
      assert_includes response.body, "期待利益が"
      assert_includes response.body, "Codex用プロンプト作成"
      assert_includes response.body, "CEO MODE"
      assert_includes response.body, "Businesses"
      assert_includes response.body, "Today"
      assert_includes response.body, "Action Candidates"
      assert_includes response.body, "Auto Revision"
      assert_includes response.body, "Auto Build"
      assert_includes response.body, "Revenue"
      assert_includes response.body, "Learning"
      assert_includes response.body, "運用・実行管理"
      assert_includes response.body, "改修・Codex管理"
      assert_includes response.body, "AI Resource / Auto Build"
      assert_includes response.body, "システム状態"
      assert_includes response.body, "Traffic Channel"
      assert_includes response.body, "SERP"
      assert_includes response.body, "学習・履歴"
      assert_includes response.body, "Daily Run Health"
      assert_includes response.body, "改訂待ち"
      assert_includes response.body, "Codex準備前"
      assert_includes response.body, "自動デプロイ可能"
      assert_includes response.body, "PR確認待ち"
      assert_includes response.body, "deploy確認待ち"
      assert_not_includes response.body, "SERP走査"
      assert_not_includes response.body, "Cron Ready"
      assert_not_includes response.body, "Google OAuth"
      assert_not_includes response.body, "Pipeline E2E"
      assert_not_includes response.body, "Execution Profiles"
      assert_not_includes response.body, "AICOO Analytics Import"
      assert_operator response.body.index("今日おすすめの事業改善 TOP10"), :<, response.body.index("Businessカード")
      assert_operator response.body.index("Businessカード"), :<, response.body.index("運用・実行管理")
      assert_operator response.body.index("運用・実行管理"), :<, response.body.index("Daily Run Health")
    end

    test "today action links open action workspace instead of business detail" do
      candidate = create_candidate!(
        title: "梅田の未確認店舗を30件確認済みにする",
        immediate_value_yen: 80_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_select "a[href='#{action_workspace_path(candidate)}']", text: /実行する|詳細/
    end

    test "shows compact serp summary without keyword details" do
      business = businesses(:suelog)
      business.business_serp_keywords.create!(
        keyword: "梅田 喫煙 カフェ",
        source: "ai_suggested",
        status: "pending",
        priority_score: 70
      )
      business.serp_analyses.create!(
        keyword: "難波 喫煙",
        analyzed_at: Time.current,
        search_engine: "google",
        device: "desktop",
        provider: "serper",
        status: "failed",
        error_message: "Rate limit"
      )
      ActionCandidate.create!(
        business:,
        title: "SERP由来の改善提案",
        status: "approved",
        action_type: "seo_improvement",
        generation_source: "serp",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "追加待ち検索クエリが1件あります。"
      assert_includes response.body, "SERP取得に失敗したBusinessが1件あります。"
      assert_includes response.body, "今日SERPから1件の改善提案が生成されています。"
      assert_includes response.body, "SERP設定"
      assert_includes response.body, "SERP E2E診断"
      assert_not_includes response.body, "梅田 喫煙 カフェ"
      assert_not_includes response.body, "Rate limit"
    end

    test "shows new business candidates near daily decision area" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "新規事業候補: 警備AI",
        description: "警備AIのLP検証",
        action_type: "build_lp",
        department: "new_business",
        generation_source: "integrated_decision",
        status: "idea",
        immediate_value_yen: 80_000,
        success_probability: 0.25,
        expected_hours: 2,
        metadata: {
          "candidate_kind" => "new_business",
          "source_query" => "警備 AI",
          "market_memo" => "上位にSaaS競合あり"
        }
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "新規事業候補"
      assert_includes response.body, candidate.title
      assert_includes response.body, "LP検証へ進める"
      assert_operator response.body.index("<h2>今日おすすめの事業改善 TOP10</h2>"), :<, response.body.index("<h2>新規事業候補</h2>")
      assert_operator response.body.index("<h2>新規事業候補</h2>"), :<, response.body.index("<h2>Businessカード</h2>")
    end

    test "orders improvements by expected profit before lower value candidates" do
      low = create_candidate!(
        title: "小さい改善",
        immediate_value_yen: 5_000,
        success_probability: 0.5,
        expected_hours: 1
      )
      high = create_candidate!(
        title: "大きい改善",
        immediate_value_yen: 80_000,
        success_probability: 0.9,
        expected_hours: 2
      )

      get owner_focus_url

      assert_response :success
      assert_operator response.body.index(high.title), :<, response.body.index(low.title)
    end

    test "shows analyzer evidence and hides abstract seo media candidates" do
      concrete = create_candidate!(
        title: "CTR0.5%の検索入口を5件書き換える",
        immediate_value_yen: 60_000,
        success_probability: 0.7,
        expected_hours: 1,
        generation_source: "business_analyzer"
      )
      concrete.update_columns(
        metadata: concrete.metadata.to_h.merge(
          "seo_action_type" => "improve_ctr_title",
          "execution_mode" => "content_creation",
          "execution_units" => [
            {
              "label" => "梅田 喫煙 居酒屋 のSEOタイトル/metaを1件改善",
              "query" => "梅田 喫煙 居酒屋",
              "target_amount" => 1,
              "estimated_minutes" => 20,
              "reason" => "高順位なのにCTRが低いため"
            }
          ],
          "evidence" => {
            "source" => [ "gsc" ],
            "issue_type" => "seo_low_ctr_titles",
            "query" => "梅田 喫煙 居酒屋",
            "page_path" => "/umeda-smoking-izakaya",
            "current_value" => 0.005,
            "benchmark_value" => 0.03,
            "target_amount" => 5,
            "target_unit" => "件",
            "expected_effect" => "+120クリック/月",
            "reason" => "平均順位5位以内にもかかわらずCTRが低いため"
          }
        )
      )
      abstract = create_candidate!(
        title: "CVを改善する",
        description: "CTAとUXを改善します。",
        immediate_value_yen: 999_999,
        success_probability: 0.9,
        expected_hours: 1,
        generation_source: "ai_business"
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, concrete.title
      assert_includes response.body, "根拠データ"
      assert_includes response.body, "作業カテゴリ: CTRタイトル改善"
      assert_includes response.body, "実行方法: 記事作成"
      assert_includes response.body, "Codex対象"
      assert_includes response.body, "これは記事作成タスクなので、Codexではなく記事作成AIまたはOwnerが実行します。"
      assert_includes response.body, "今日やる単位"
      assert_includes response.body, "1. 梅田 喫煙 居酒屋 のSEOタイトル/metaを1件改善（20分）"
      assert_includes response.body, "根拠: GSC"
      assert_includes response.body, "対象: 「梅田 喫煙 居酒屋」 / /umeda-smoking-izakaya"
      assert_includes response.body, "現在: 0.5%"
      assert_includes response.body, "目標: 3.0%"
      assert_includes response.body, "実施量: 5件"
      assert_not_includes response.body, abstract.title
      assert_not_includes response.body, "Codex用プロンプト作成"
    end

    test "includes auto revision task as codex improvement" do
      candidate = create_candidate!(
        title: "流入上位10ページに店舗リンクを30件追加する",
        immediate_value_yen: 30_000,
        success_probability: 0.7,
        expected_hours: 1
      )
      candidate.update_columns(
        metadata: candidate.metadata.to_h.merge(
          "seo_action_type" => "add_shop_links",
          "execution_units" => [
            {
              "label" => "流入上位記事に店舗リンクを10件追加",
              "page_path" => "流入上位記事",
              "target_amount" => 10,
              "estimated_minutes" => 40,
              "reason" => "回遊が弱いため"
            }
          ],
          "evidence" => {
            "source" => [ "ga4", "business_db" ],
            "issue_type" => "seo_internal_links_shortage",
            "page_path" => "/umeda-smoking-izakaya",
            "current_value" => 1.1,
            "benchmark_value" => 1.3,
            "target_amount" => 30,
            "target_unit" => "件",
            "expected_effect" => "Views/Session +0.3",
            "reason" => "回遊が弱いため"
          }
        )
      )
      task = AutoRevisionTask.create!(
        business: candidate.business,
        action_candidate: candidate,
        title: "店舗リンク30件追加をCodexで実装する",
        execution_prompt: "流入上位10ページに店舗リンクを30件追加してください。",
        status: "waiting_approval",
        risk_level: "low",
        priority_score: 10_000
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, task.title
      assert_includes response.body, export_codex_prompt_auto_revision_task_path(task)
      assert_includes response.body, "Codex準備前"
      assert_includes response.body, "1件"
    end

    test "warns when analyzer candidate has no execution units" do
      candidate = create_candidate!(
        title: "CTR0.5%の検索入口を5件書き換える",
        immediate_value_yen: 50_000,
        success_probability: 0.7,
        expected_hours: 1,
        generation_source: "business_analyzer"
      )
      candidate.update_columns(
        metadata: candidate.metadata.to_h.merge(
          "seo_action_type" => "improve_ctr_title",
          "evidence" => {
            "source" => [ "gsc" ],
            "issue_type" => "seo_low_ctr_titles",
            "query" => "梅田 喫煙 居酒屋",
            "current_value" => 0.005,
            "benchmark_value" => 0.03,
            "target_amount" => 5,
            "target_unit" => "件"
          }
        )
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, candidate.title
      assert_includes response.body, "今日やる単位が未生成です。"
    end

    test "shows codex submission waiting summary" do
      profile = BusinessExecutionProfile.create!(
        business: businesses(:suelog),
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: "/apps/suelog",
        github_repository: "https://github.com/example/suelog",
        test_command: "bin/rails test",
        deploy_command: "bin/deploy",
        require_manual_approval: false,
        codex_enabled: true,
        codex_project_folder: "/workspace/suelog",
        codex_repository_url: "https://github.com/example/suelog",
        codex_auto_submit_enabled: true
      )
      candidate = create_candidate!(
        title: "Codex Cloudへ送る改善",
        immediate_value_yen: 30_000,
        success_probability: 0.7,
        expected_hours: 1
      )
      task = AutoRevisionTask.from_action_candidate(candidate)
      task.approve!
      task.update!(risk_level: "low")
      Aicoo::CodexSubmissionBuilder.new(task).call

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "Codex送信待ち"
      assert_includes response.body, "Codex送信待ちを見る"
      assert_includes response.body, "Codex手動送信一覧へ"
      assert_includes response.body, "ready"
      assert_includes response.body, "1件"
      assert_equal profile, task.reload.codex_submission.business_execution_profile
    end

    test "defer hides improvement from current ranking" do
      candidate = create_candidate!(
        title: "後で確認する改善",
        immediate_value_yen: 40_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      patch defer_owner_focus_path(task_key: "action_candidate:#{candidate.id}")
      assert_redirected_to owner_focus_path
      follow_redirect!

      assert_response :success
      assert_not_includes response.body, candidate.title
    end

    test "does not show system business as business card or blocker" do
      system_business = Business.create!(
        name: "AICOO Analytics Import",
        description: "system import holder",
        status: "launched"
      )
      ActionCandidate.create!(
        business: system_business,
        title: "System-only candidate",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 999_999,
        success_probability: 1,
        expected_hours: 1
      )
      create_candidate!(
        title: "通常Business改善",
        immediate_value_yen: 10_000,
        success_probability: 0.8,
        expected_hours: 1
      )

      get owner_focus_url

      assert_response :success
      assert_includes response.body, "通常Business改善"
      assert_not_includes response.body, "AICOO Analytics Import"
      assert_not_includes response.body, "System-only candidate"
    end

    private

    def create_candidate!(attributes)
      ActionCandidate.create!(
        {
          business: businesses(:suelog),
          status: "approved",
          action_type: "seo_improvement",
          evaluation_reason: "CTRが7日平均より低下しています。タイトル改善で利益増加が見込めます。"
        }.merge(attributes)
      )
    end
  end
end
