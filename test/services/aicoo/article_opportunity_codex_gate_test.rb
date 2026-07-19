require "test_helper"

module Aicoo
  class ArticleOpportunityCodexGateTest < ActiveSupport::TestCase
    setup do
      AutoRevisionTask.delete_all
      AicooDataSnapshot.where(source_type: "article_analytics").delete_all
      @business = Business.create!(name: "吸えログ Codex Gate", auto_revision_mode: "approval", metadata: { "business_key" => "suelog" })
      @profile = @business.create_business_execution_profile!(
        repository_name: "suelog",
        repository_type: "rails",
        repository_path: "/apps/suelog",
        github_repository: "https://github.com/example/suelog",
        test_command: "bin/rails test",
        lint_command: "bin/rails zeitwerk:check",
        deploy_command: "bin/deploy",
        codex_enabled: true,
        codex_workspace_name: "workspace",
        codex_project_folder: "/apps/suelog",
        codex_repository_url: "https://github.com/example/suelog",
        codex_base_branch: "main",
        codex_working_branch_prefix: "aicoo/",
        codex_auto_submit_enabled: false,
        codex_auto_merge_enabled: false,
        codex_auto_deploy_enabled: false,
        codex_risk_limit: "medium",
        require_manual_approval: false
      )
      @snapshot = create_snapshot(article_id: 501, path: "/articles/umeda-smoking-cafe")
    end

    test "new analyzer production candidate passes gate when brief is safe and approved" do
      candidate = create_article_candidate(status: "approved")

      result = ArticleOpportunityCodexGate.call(candidate)

      assert result.eligible?, result.reasons.join(",")
      assert_equal "low", result.risk_level
      assert_equal "codex", result.executor
      assert_equal "cloud", result.execution_mode
      assert_equal @profile, result.profile
    end

    test "archived comparison candidate is blocked" do
      candidate = create_article_candidate(status: "archived", production_candidate: false)

      result = ArticleOpportunityCodexGate.call(candidate)

      assert_not result.eligible?
      assert_includes result.reasons, "not_production_candidate"
      assert_includes result.reasons, "inactive_candidate"
    end

    test "human and research required candidates are blocked" do
      candidate = create_article_candidate(status: "approved", opportunity_type: "shop_addition")
      metadata = candidate.metadata.to_h
      metadata["execution_brief"]["execution"]["codex_eligible"] = false
      metadata["execution_brief"]["execution"]["human_required"] = true
      candidate.update_columns(metadata:)

      result = ArticleOpportunityCodexGate.call(candidate)

      assert_not result.eligible?
      assert_includes result.reasons, "blocked_opportunity_type"
      assert_includes result.reasons, "human_required"
    end

    test "internal link addition requires concrete existing link candidates" do
      candidate = create_article_candidate(status: "approved", opportunity_type: "internal_link_addition")
      metadata = candidate.metadata.to_h
      metadata["execution_brief"]["recommended_changes"].first["evidence"]["candidate_links"] = []
      candidate.update_columns(metadata:)

      result = ArticleOpportunityCodexGate.call(candidate)

      assert_not result.eligible?
      assert_includes result.reasons, "internal_link_targets_missing"
    end

    test "external url in brief blocks codex" do
      candidate = create_article_candidate(status: "approved")
      metadata = candidate.metadata.to_h
      metadata["execution_brief"]["recommended_changes"].first["evidence"]["candidate_links"] = [
        { "path" => "/articles/ok", "url" => "https://it-trend.jp/log_management/article/84-0008" }
      ]
      candidate.update_columns(metadata:)

      result = ArticleOpportunityCodexGate.call(candidate)

      assert_not result.eligible?
      assert_includes result.reasons, "external_url_detected"
    end

    test "newer snapshot supersedes candidate" do
      candidate = create_article_candidate(status: "approved")
      create_snapshot(article_id: 501, path: "/articles/umeda-smoking-cafe", captured_at: 1.minute.from_now)

      result = ArticleOpportunityCodexGate.call(candidate)

      assert_not result.eligible?
      assert_includes result.reasons, "superseded_by_newer_snapshot"
    end

    test "auto revision task uses article opportunity prompt and does not duplicate active task" do
      candidate = create_article_candidate(status: "approved")

      assert_difference("AutoRevisionTask.count", 1) do
        task = AutoRevisionTask.from_action_candidate(candidate, generated_by: "test")
        assert_includes task.execution_prompt, "指示された対象以外は変更しない"
        assert_includes task.execution_prompt, "DB Migration禁止"
        assert_includes task.execution_prompt, "main直接push禁止"
        assert_equal "ctr_improvement", task.metadata["opportunity_type"]
        assert_equal false, task.metadata["auto_merge_enabled"]
        assert_equal false, task.metadata["auto_deploy_enabled"]
      end

      assert_no_difference("AutoRevisionTask.count") do
        AutoRevisionTask.from_action_candidate(candidate, generated_by: "test")
      end
    end

    private

    def create_snapshot(article_id:, path:, captured_at: Time.current)
      AicooDataSnapshot.create!(
        source_type: "article_analytics",
        source_id: article_id,
        captured_at:,
        payload: {
          "business_id" => @business.id,
          "article_id" => article_id,
          "normalized_path" => path,
          "snapshot_status" => "active"
        }
      )
    end

    def create_article_candidate(status:, opportunity_type: "ctr_improvement", production_candidate: true)
      ActionCandidate.create!(
        business: @business,
        title: "梅田 喫煙 カフェのtitle/metaを主要クエリに合わせて見直す",
        action_type: "article_update",
        status:,
        generation_source: "business_analyzer",
        immediate_value_yen: 1_000,
        success_probability: 1,
        execution_prompt: "execution_briefに従ってtitle/metaを見直してください。",
        metadata: metadata_for(opportunity_type:, production_candidate:)
      )
    end

    def metadata_for(opportunity_type:, production_candidate:)
      {
        "value_model_name" => ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME,
        "analysis_source" => "article_analytics_snapshot",
        "production_candidate" => production_candidate,
        "snapshot_id" => @snapshot.id,
        "article_id" => 501,
        "article_path" => "/articles/umeda-smoking-cafe",
        "opportunity_type" => opportunity_type,
        "expected_improvement_score" => 10.5,
        "codex_eligible" => true,
        "execution_brief" => {
          "target" => {
            "business_id" => @business.id,
            "article_id" => 501,
            "article_title" => "梅田 喫煙 カフェ",
            "article_path" => "/articles/umeda-smoking-cafe",
            "target_url" => "https://suelog.jp/articles/umeda-smoking-cafe",
            "target_type" => "existing_article",
            "improvement_type" => opportunity_type,
            "snapshot_id" => @snapshot.id
          },
          "current_state" => { "impressions" => 1200, "ctr" => 0.005, "average_position" => 14 },
          "evidence" => { "analyzer" => { "expected_improvement_score" => 10.5 } },
          "recommended_changes" => [
            {
              "change_type" => "title_meta_review",
              "target_element" => "title/meta_description",
              "instruction" => "主要検索クエリに合わせて見直す",
              "evidence" => {
                "candidate_links" => [
                  { "path" => "/articles/namba-smoking-izakaya", "url" => "https://suelog.jp/articles/namba-smoking-izakaya" }
                ]
              },
              "before" => { "title" => "梅田 喫煙 カフェ" },
              "after_goal" => "検索意図と記事内容を一致させる",
              "automation_level" => "codex_possible",
              "requires_research" => false,
              "requires_human_review" => true
            }
          ],
          "completion_conditions" => [ "対象記事とURLが一致している", "titleが対象クエリの検索意図と一致している" ],
          "expected_result" => { "expected_improvement_score" => 10.5 },
          "execution" => {
            "codex_eligible" => true,
            "human_required" => false,
            "research_required" => false,
            "rollback_possible" => true,
            "estimated_work_hours" => 0.3
          },
          "missing_information" => [],
          "safety" => {
            "factual_risk" => "low",
            "prohibited_actions" => [ "未確認店舗情報の公開", "外部URLを自サイトURLとして扱う" ]
          }
        }
      }
    end
  end
end
