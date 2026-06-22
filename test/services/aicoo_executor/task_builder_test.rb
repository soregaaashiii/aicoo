require "test_helper"

module AicooExecutor
  class TaskBuilderTest < ActiveSupport::TestCase
    test "builds executor task from revenue execution" do
      candidate = create_candidate(title: "LP検証を実行する")
      execution = create_revenue_execution(
        source_type: "candidate",
        source_id: candidate.id,
        title: candidate.title,
        estimated_work_minutes: 90
      )

      task = TaskBuilder.from_revenue_execution(execution)

      assert_equal "実行計画: LP検証を実行する", task.title
      assert_equal "lab_candidate", task.source_type
      assert_equal candidate.id, task.source_id
      assert_equal "lp_creation", task.execution_type
      assert_equal 60, task.estimated_minutes
      assert_equal "approval_pending", task.status
      assert_includes task.execution_prompt, "LPを作成"
      assert_common_prompt_text(task.execution_prompt)
    end

    test "infers shop import from action candidate" do
      action_candidate = create_action_candidate(title: "梅田の店舗追加を100件行う")
      action_candidate.update_column(:action_type, "shop_import")
      execution = create_revenue_execution(
        source_type: "action_candidate",
        source_id: action_candidate.id,
        title: action_candidate.title,
        estimated_work_minutes: 120
      )

      task = TaskBuilder.from_revenue_execution(execution)

      assert_equal "action_candidate", task.source_type
      assert_equal action_candidate.id, task.source_id
      assert_equal "shop_import", task.execution_type
      assert_includes task.execution_prompt, "吸えログへ店舗を追加"
      assert_includes task.execution_prompt, "重複チェック"
      assert_includes task.execution_prompt, "喫煙情報"
      assert_includes task.execution_prompt, "既存データ破壊禁止"
      assert_common_prompt_text(task.execution_prompt)
    end

    test "generates codex-ready prompt for each execution type" do
      cases = [
        {
          expected_type: "seo_content",
          record: create_action_candidate(title: "SEO記事を作る", action_type: "seo_article"),
          source_type: "action_candidate",
          terms: [ "SEOタイトル", "meta description", "内部リンク", "既存記事を壊さない" ]
        },
        {
          expected_type: "seo_update",
          record: create_action_candidate(title: "既存記事を更新する", action_type: "seo_improvement"),
          source_type: "action_candidate",
          terms: [ "既存URL維持", "変更前後", "内部リンク" ]
        },
        {
          expected_type: "lp_creation",
          record: create_candidate(title: "LP検証", experiment_type: "lp"),
          source_type: "candidate",
          terms: [ "preview", "本番公開しない", "CTA計測を壊さない" ]
        },
        {
          expected_type: "market_research",
          record: create_action_candidate(title: "市場調査を行う", action_type: "market_research"),
          source_type: "action_candidate",
          terms: [ "根拠", "次アクション候補", "構造化" ]
        },
        {
          expected_type: "customer_interview",
          record: create_action_candidate(title: "顧客インタビューを設計する", action_type: "other"),
          source_type: "action_candidate",
          terms: [ "質問リスト", "仮説検証", "記録フォーマット" ]
        },
        {
          expected_type: "data_collection",
          record: create_action_candidate(title: "GSCデータ収集を行う", action_type: "other"),
          source_type: "action_candidate",
          terms: [ "保存先", "既存データ上書き禁止", "データ取得" ]
        },
        {
          expected_type: "data_preparation",
          record: create_action_candidate(
            title: "Judge補正に必要な不足データを増やす",
            action_type: "data_preparation",
            metadata: { "metric_rule" => "correction_readiness" },
            execution_prompt: "ActionResultが不足しています"
          ),
          source_type: "action_candidate",
          terms: [ "Judge補正やproxy_score補正", "ActionResult", "BusinessMetricDaily" ]
        },
        {
          expected_type: "custom",
          record: create_action_candidate(title: "収益行動を整理する", action_type: "other"),
          source_type: "action_candidate",
          terms: [ "汎用テンプレート", "完了条件" ]
        }
      ]

      cases.each do |test_case|
        execution = create_revenue_execution(
          source_type: test_case.fetch(:source_type),
          source_id: test_case.fetch(:record).id,
          title: test_case.fetch(:record).title
        )

        task = TaskBuilder.from_revenue_execution(execution)

        assert_equal test_case.fetch(:expected_type), task.execution_type
        assert_common_prompt_text(task.execution_prompt)
        test_case.fetch(:terms).each do |term|
          assert_includes task.execution_prompt, term
        end
      end
    end

    test "builds inferred executor task directly from action candidate" do
      action_candidate = create_action_candidate(title: "SEO記事を作る", action_type: "seo_article")

      task = TaskBuilder.from_action_candidate(action_candidate)

      assert_equal "action_candidate", task.source_type
      assert_equal action_candidate.id, task.source_id
      assert_equal "seo_content", task.execution_type
      assert_equal "approval_pending", task.status
      assert_common_prompt_text(task.execution_prompt)
    end

    private

    def assert_common_prompt_text(prompt)
      assert_includes prompt, "## 目的"
      assert_includes prompt, "## 対象"
      assert_includes prompt, "## 作業範囲"
      assert_includes prompt, "## 絶対に壊してはいけないもの"
      assert_includes prompt, "## 実装手順"
      assert_includes prompt, "確認コマンド"
      assert_includes prompt, "## 完了報告に含めるもの"
      assert_includes prompt, "db:drop / db:reset / drop database は絶対禁止"
      assert_includes prompt, "既存機能を壊さない"
      assert_includes prompt, "bin/rails test"
    end

    def create_candidate(attributes = {})
      AicooLabExperimentCandidate.create!(
        {
          title: "Executor candidate",
          description: "Executor candidate description",
          experiment_type: "lp",
          market_category: "executor market",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60,
          rationale: "Executor rationale"
        }.merge(attributes)
      )
    end

    def create_action_candidate(attributes = {})
      business = Business.create!(name: "Executor business")
      ActionCandidate.create!(
        {
          business:,
          title: "Executor action",
          action_type: "seo_article",
          status: "idea",
          immediate_value_yen: 80_000,
          success_probability: 0.25,
          expected_hours: 1,
          cost_yen: 0
        }.merge(attributes)
      )
    end

    def create_revenue_execution(attributes = {})
      AicooRevenueExecution.create!(
        {
          source_type: "candidate",
          source_id: 1,
          title: "Executor revenue execution",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          revenue_total_value_yen: 12_500,
          estimated_work_minutes: 60,
          budget_yen: 0,
          revenue_score: 10,
          status: "planned"
        }.merge(attributes)
      )
    end
  end
end
