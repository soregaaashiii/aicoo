require "test_helper"
require "rake"

class AicooActionCandidateExecutionReadinessRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:cleanup_action_candidate_execution_readiness")
    Rake::Task["aicoo:cleanup_action_candidate_execution_readiness"].reenable
  end

  test "cleanup converts unsafe non ready codex candidate" do
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "滞在時間が短いページを改善する",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      metadata: {}
    )
    candidate.update_columns(
      action_type: "seo_improvement",
      execution_prompt: "滞在時間が短いページを改善してください。",
      metadata: {
        "codex_eligible" => true,
        "auto_revision" => true,
        "concrete_task" => "滞在時間が短いページを改善する"
      },
      updated_at: Time.current
    )

    ENV["APPLY"] = "1"
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_candidate_execution_readiness"].invoke
    end

    candidate.reload
    assert_includes output, "converted_to_data_preparation=1"
    assert_equal "data_preparation", candidate.action_type
    assert_equal false, candidate.metadata["codex_eligible"]
    assert_equal false, candidate.metadata["auto_revision"]
    assert_equal "needs_target", candidate.metadata["execution_readiness"]
    assert_equal "not_ready_for_codex", candidate.metadata.dig("execution_readiness_cleanup", "reason")

    ENV.delete("APPLY")
    Rake::Task["aicoo:cleanup_action_candidate_execution_readiness"].reenable
    second_output, = capture_io do
      Rake::Task["aicoo:cleanup_action_candidate_execution_readiness"].invoke
    end

    assert_includes second_output, "converted_to_data_preparation=0"
    assert_includes second_output, "skipped_already_cleaned=1"
    assert_match(/candidate_ids=\s*$/, second_output)
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup keeps ready codex candidate" do
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "梅田 喫煙 カフェのtitleを改善する",
      action_type: "seo_improvement",
      status: "idea",
      execution_prompt: "SEOタイトルを改善してください。",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      metadata: {
        "target_url" => "/",
        "target_query" => "梅田 喫煙 カフェ",
        "concrete_task" => "SEOタイトルを改善する",
        "target_files" => [ "app/views/articles/show.html.erb" ],
        "completion_criteria" => [ "SEOタイトルが変更されていること" ],
        "before" => "旧タイトル",
        "after" => "新タイトル",
        "codex_eligible" => true,
        "auto_revision" => true
      }
    )

    ENV["APPLY"] = "1"
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_candidate_execution_readiness"].invoke
    end

    assert_includes output, "converted_to_data_preparation=0"
    assert_equal "seo_improvement", candidate.reload.action_type
    assert_equal "ready", candidate.metadata["execution_readiness"]
  ensure
    ENV.delete("APPLY")
  end
end
