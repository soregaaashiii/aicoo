require "test_helper"

module Owner
  class TodayOwnerActionTest < ActionDispatch::IntegrationTest
    setup do
      ActionCandidate.update_all(status: "done")
      AutoRevisionTask.delete_all
      AicooDailyRunStep.delete_all
      AicooDailyRun.delete_all
      Business.where(created_by_aicoo: true).update_all(resource_status: "archived")
    end

    test "waiting approval candidate is shown in Today" do
      candidate, task = create_waiting_approval!(title: "承認待ちの記事改訂", expected_value_yen: 100_000)

      item = board_item(candidate)

      assert_equal task, item.record
      assert_equal "auto_revision_task", item.source_type
      assert_equal "waiting_approval", item.current_status
      assert item.approval_required
    end

    test "waiting approval candidates are ordered by expected yen in every Today mode" do
      low, = create_waiting_approval!(title: "低期待値の承認", expected_value_yen: 20_000)
      high, = create_waiting_approval!(title: "高期待値の承認", expected_value_yen: 120_000)

      %w[revenue learning balanced].each do |mode|
        ids = board(mode:).items.map(&:stable_id)

        assert_operator ids.index(stable_id(high)), :<, ids.index(stable_id(low)), mode
      end
    end

    test "high value approval is ranked above lower value manual work" do
      approval, = create_waiting_approval!(title: "高期待値の承認", expected_value_yen: 90_000)
      manual = create_candidate!(title: "電話確認を行う", expected_value_yen: 10_000, execution_mode: "manual_operation")

      ids = board.items.map(&:stable_id)

      assert_operator ids.index(stable_id(approval)), :<, ids.index(stable_id(manual))
    end

    test "existing AutoRevisionTask does not hide its waiting approval candidate" do
      candidate, task = create_waiting_approval!(title: "改修キュー内の承認待ち", expected_value_yen: 70_000)

      items = board.items.select { |item| item.stable_id == stable_id(candidate) }

      assert_equal 1, items.size
      assert_equal task, items.first.record
    end

    test "approved queued task is not shown in Today" do
      candidate, = create_task_candidate!(status: "queued", title: "承認済み実行待ち")

      assert_nil board_item(candidate)
      assert_equal "auto_revision_queued", candidate.reload.metadata["today_exclusion_reason"]
    end

    test "running task is not shown in Today" do
      candidate, = create_task_candidate!(status: "running", title: "自動実行中")

      assert_nil board_item(candidate)
      assert_equal "auto_revision_in_progress", candidate.reload.metadata["today_exclusion_reason"]
    end

    test "ActionCandidate and AutoRevisionTask are represented once in Today" do
      candidate, task = create_waiting_approval!(title: "重複させない承認待ち", expected_value_yen: 80_000)

      matching = board.items.select { |item| item.stable_id == stable_id(candidate) }

      assert_equal 1, matching.size
      assert_equal task, matching.first.record
      assert_equal candidate.id, task.action_candidate_id
    end

    test "waiting approval has a direct approval action and task detail link" do
      candidate, task = create_waiting_approval!(title: "Todayから承認できる改修", expected_value_yen: 60_000)

      get owner_focus_url

      assert_response :success
      assert_select "tr[data-today-item-id='#{stable_id(candidate)}']" do
        assert_select "form[action='#{approve_auto_revision_task_path(task)}']"
        assert_select "a[href='#{auto_revision_task_path(task)}']", text: "承認内容を見る"
      end
    end

    test "approving from Today updates the same queue task" do
      candidate, task = create_waiting_approval!(title: "同じキューを更新する承認", expected_value_yen: 50_000)

      assert_no_difference [ "ActionCandidate.count", "AutoRevisionTask.count" ] do
        patch approve_auto_revision_task_url(task)
      end

      assert_redirected_to auto_revision_task_url(task)
      assert_equal "ready_for_codex", task.reload.status
      assert_equal candidate.id, task.action_candidate_id
      assert_nil board_item(candidate)
    end

    test "rendering a waiting approval never creates duplicate candidate or task records" do
      candidate, task = create_waiting_approval!(title: "表示だけでは複製しない", expected_value_yen: 40_000)

      assert_no_difference [ "ActionCandidate.count", "AutoRevisionTask.count" ] do
        2.times { get owner_focus_url }
      end

      assert_equal task.id, candidate.auto_revision_tasks.reload.sole.id
    end

    test "shop addition candidate is shown in Today" do
      candidate = create_candidate!(
        title: "梅田の掲載店舗を追加する",
        expected_value_yen: 32_000,
        execution_mode: "data_operation",
        action_type: "data_preparation",
        metadata: {
          "target_record_id" => 501,
          "target_name" => "梅田エリア",
          "target_query" => "梅田 居酒屋"
        }
      )

      assert board_item(candidate)
    end

    test "Suelog smoking confirmation uses shop metadata as its Today target" do
      candidate = create_candidate!(
        title: "喫煙情報を確認する",
        expected_value_yen: 28_000,
        execution_mode: "manual_operation",
        action_type: "smoking_info_verify",
        generation_source: "suelog_db",
        metadata: {
          "target_record_id" => nil,
          "shop_id" => 601,
          "shop_name" => "確認対象店舗",
          "target_query" => "",
          "action_plan" => {
            "summary" => "確認対象店舗の喫煙情報を確認する",
            "target" => nil,
            "owner_next_step" => "店舗へ電話して確認する",
            "execution_steps" => [ "店舗へ電話して確認する" ]
          }
        }
      )

      item = board_item(candidate)

      assert item
      assert_equal "確認対象店舗 #601", item.target
    end

    test "other Business code revision and LP improvement are shown in Today" do
      code_candidate, = create_task_candidate!(
        status: "waiting_approval",
        title: "名刺共有アプリのコードを改訂する",
        expected_value_yen: 52_000,
        business: businesses(:cards),
        action_type: "feature_development"
      )
      lp_candidate, = create_task_candidate!(
        status: "waiting_approval",
        title: "名刺共有アプリのLPを改善する",
        expected_value_yen: 41_000,
        business: businesses(:cards),
        action_type: "build_lp"
      )

      items = board.items

      assert items.any? { |item| item.stable_id == stable_id(code_candidate) && item.business_name == businesses(:cards).name }
      assert items.any? { |item| item.stable_id == stable_id(lp_candidate) && item.business_name == businesses(:cards).name }
    end

    test "Today is not limited to article candidates" do
      article = create_candidate!(
        title: "吸えログの記事を改訂する",
        expected_value_yen: 20_000,
        execution_mode: "content_creation",
        action_type: "article_update"
      )
      shop = create_candidate!(
        title: "店舗データを追加する",
        expected_value_yen: 30_000,
        execution_mode: "data_operation",
        action_type: "data_preparation",
        metadata: { "target_record_id" => 701, "target_name" => "店舗登録対象" }
      )

      ids = board.items.map(&:stable_id)

      assert_includes ids, stable_id(article)
      assert_includes ids, stable_id(shop)
    end

    test "same article action is shown once while different targets remain separate" do
      first = create_candidate!(
        title: "比較記事を作成する",
        expected_value_yen: 20_000,
        execution_mode: "content_creation",
        action_type: "seo_improvement",
        generation_source: "manual",
        metadata: {
          "target_query" => "吸えログ 比較",
          "target_url" => "/",
          "work_type" => "article_update"
        }
      )
      second = create_candidate!(
        title: "比較記事を作成する",
        expected_value_yen: 25_000,
        execution_mode: "content_creation",
        action_type: "seo_improvement",
        generation_source: "manual",
        metadata: {
          "target_query" => "吸えログ 比較",
          "target_url" => "/",
          "work_type" => "article_update"
        }
      )

      matching = board.items.select { |item| [ stable_id(first), stable_id(second) ].include?(item.stable_id) }

      assert_equal 1, matching.size
      assert_equal stable_id(second), matching.sole.stable_id
    end

    test "failed task is shown for owner retry decision" do
      candidate, task = create_task_candidate!(status: "failed", title: "失敗後に再実行を判断する")

      item = board_item(candidate)

      assert_equal task, item.record
      assert_equal "failed", item.current_status
      assert_equal "失敗内容を確認して再実行を判断する", item.owner_next_step
    end

    test "higher expected yen from another Business ranks first" do
      suelog = create_candidate!(title: "吸えログの手作業", expected_value_yen: 20_000, execution_mode: "manual_operation")
      cards = create_candidate!(
        title: "名刺共有アプリの手作業",
        expected_value_yen: 90_000,
        execution_mode: "manual_operation",
        business: businesses(:cards)
      )

      ids = board.items.map(&:stable_id)

      assert_operator ids.index(stable_id(cards)), :<, ids.index(stable_id(suelog))
    end

    test "Today and revision queue use the same expected yen order for common candidates" do
      low, = create_waiting_approval!(title: "低期待値の改修", expected_value_yen: 30_000)
      high, = create_waiting_approval!(
        title: "高期待値の他事業改修",
        expected_value_yen: 80_000,
        business: businesses(:cards)
      )

      today_ids = board.items.map(&:stable_id) & [ stable_id(low), stable_id(high) ]
      queue_candidate_ids = Aicoo::Owner::AutoRevisionLoopBoard.new(limit: 100).call.rows
        .filter_map(&:action_candidate)
        .map(&:id) & [ low.id, high.id ]

      assert_equal [ stable_id(high), stable_id(low) ], today_ids
      assert_equal [ high.id, low.id ], queue_candidate_ids
    end

    test "LP generation plan links to its execution review" do
      candidate, task = create_waiting_approval!(title: "LP生成計画を確認する", expected_value_yen: 75_000)
      task.update!(
        metadata: task.metadata.merge(
          "workflow_type" => "lp_generation_plan",
          "generation_run_id" => "plan-123"
        )
      )

      item = board_item(candidate)

      assert_equal(
        landing_page_plan_review_business_access_settings_path(candidate.business, plan_id: "plan-123"),
        item.detail_url
      )
      assert_equal "実行前レビューを確認して承認する", item.owner_next_step
    end

    private

    def board(mode: "revenue")
      Aicoo::TodayActionBoard.new(mode:, per_page: 100).call
    end

    def board_item(candidate)
      board.items.find { |item| item.stable_id == stable_id(candidate) }
    end

    def stable_id(candidate)
      "action_candidate:#{candidate.id}"
    end

    def create_waiting_approval!(title:, expected_value_yen:, business: businesses(:suelog))
      create_task_candidate!(status: "waiting_approval", title:, expected_value_yen:, business:)
    end

    def create_task_candidate!(status:, title:, expected_value_yen: 50_000, business: businesses(:suelog), action_type: "seo_improvement")
      candidate = create_candidate!(title:, expected_value_yen:, execution_mode: "code_revision", business:, action_type:)
      candidate.auto_revision_tasks.destroy_all
      task = AutoRevisionTask.create!(
        action_candidate: candidate,
        business: candidate.business,
        title:,
        execution_prompt: candidate.execution_prompt,
        priority_score: expected_value_yen,
        generated_by: "today_owner_action_test",
        risk_level: "low",
        status:,
        approved_at: (Time.current unless status == "waiting_approval"),
        metadata: {
          "approval_required_reason" => "実行前レビューを確認してください。",
          "target_url" => "/",
          "action_type" => candidate.action_type
        }
      )
      [ candidate, task ]
    end

    def create_candidate!(
      title:,
      expected_value_yen:,
      execution_mode:,
      business: businesses(:suelog),
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      metadata: {}
    )
      base_metadata = {
        "execution_mode" => execution_mode,
        "manual_task_creation_only" => true,
        "target_record_id" => 123,
        "target_url" => "/",
        "target_query" => title,
        "concrete_task" => title,
        "target_files" => [ "app/views/articles/show.html.erb" ],
        "completion_criteria" => [ "変更内容を確認できること" ],
        "before" => "変更前",
        "after" => "変更後",
        "action_value_model" => {
          "expected_value_if_action_yen" => expected_value_yen,
          "expected_value_if_no_action_yen" => 0,
          "execution_cost_yen" => 0
        },
        "action_plan" => {
          "summary" => title,
          "target" => "対象レコード #123",
          "owner_next_step" => "対象を確認する",
          "execution_steps" => [ "対象を確認する" ]
        }
      }
      merged_metadata = base_metadata.deep_merge(metadata.deep_stringify_keys)

      candidate = ActionCandidate.create!(
        business:,
        title:,
        status: "approved",
        action_type:,
        generation_source:,
        execution_prompt: "#{title}を実行してください。",
        immediate_value_yen: expected_value_yen,
        expected_hours: 1,
        success_probability: 0.8,
        evaluation_reason: "Today owner action test",
        metadata: merged_metadata
      )
      candidate.update_columns(
        expected_profit_yen: expected_value_yen,
        expected_revenue_value_yen: expected_value_yen,
        expected_total_value_yen: expected_value_yen,
        final_expected_value_yen: expected_value_yen
      )
      candidate
    end
  end
end
