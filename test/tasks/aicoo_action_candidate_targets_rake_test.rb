require "test_helper"
require "rake"

class AicooActionCandidateTargetsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:repair_action_candidate_target_urls")
    Rake::Task["aicoo:repair_action_candidate_target_urls"].reenable
  end

  test "repair task exists and runs in dry run mode" do
    assert Rake::Task.task_defined?("aicoo:repair_action_candidate_target_urls")

    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "外部URL修復対象",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      metadata: {
        "target_url" => "https://it-trend.jp/log_management/article/84-0008",
        "source_query" => "吸えログ 比較"
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:repair_action_candidate_target_urls"].invoke
    end

    assert_includes output, "mode=dry_run"
    assert_includes output, "target_url_repairs="
    assert_includes output, "duplicate_groups="
  ensure
    ENV.delete("APPLY")
  end
end
