require "test_helper"

module Aicoo
  class ActionCandidateExecutionReadinessTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
    end

    test "candidate without target url is not codex eligible" do
      candidate = build_candidate(metadata: ready_metadata.except("target_url"))

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "needs_target", result.readiness
      assert_equal false, result.codex_eligible
      assert_equal false, result.auto_revision
      assert_includes result.missing_items, "target_url_or_target_record_id"
    end

    test "candidate without target query or metric is not codex eligible" do
      candidate = build_candidate(metadata: ready_metadata.except("target_query"))

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "needs_query", result.readiness
      assert_equal false, result.codex_eligible
      assert_includes result.missing_items, "target_query"
    end

    test "candidate without completion criteria is not codex eligible" do
      candidate = build_candidate(metadata: ready_metadata.except("completion_criteria"))

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "blocked", result.readiness
      assert_equal false, result.codex_eligible
      assert_includes result.missing_items, "completion_criteria"
    end

    test "candidate without file changes is not codex eligible" do
      candidate = build_candidate(metadata: ready_metadata.except("target_files"))

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "blocked", result.readiness
      assert_equal false, result.codex_eligible
      assert_includes result.missing_items, "file_changes"
    end

    test "ready candidate is codex eligible" do
      candidate = build_candidate(metadata: ready_metadata)

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "ready", result.readiness
      assert_equal true, result.codex_eligible
      assert_equal true, result.auto_revision
      assert_empty result.missing_items
    end

    test "data preparation candidate is not auto revised" do
      candidate = build_candidate(action_type: "data_preparation", metadata: ready_metadata)

      result = ActionCandidateExecutionReadiness.call(candidate)

      assert_equal "needs_target", result.readiness
      assert_equal false, result.codex_eligible
      assert_equal false, result.auto_revision
    end

    private

    def build_candidate(action_type: "seo_improvement", metadata:)
      ActionCandidate.new(
        business: @business,
        title: "梅田 喫煙 カフェのtitleを改善する",
        action_type:,
        status: "idea",
        execution_prompt: "SEOタイトルを旧タイトルから新タイトルへ変更してください。",
        metadata:
      )
    end

    def ready_metadata
      {
        "target_url" => "/",
        "target_query" => "梅田 喫煙 カフェ",
        "concrete_task" => "SEOタイトルとmeta descriptionを改善する",
        "target_files" => [ "app/views/articles/show.html.erb" ],
        "completion_criteria" => [ "SEOタイトルが変更されていること" ],
        "before" => "旧タイトル",
        "after" => "新タイトル",
        "auto_revision" => true
      }
    end
  end
end
