require "test_helper"
require "rake"

class AicooActionCandidateTargetsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:repair_action_candidate_target_urls")
    Rake::Task["aicoo:repair_action_candidate_target_urls"].reenable
  end

  test "repair task exists and runs in dry run mode" do
    assert Rake::Task.task_defined?("aicoo:repair_action_candidate_target_urls")

    candidate = ActionCandidate.create!(
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
    candidate.update_columns(
      metadata: {
        "target_url" => "https://it-trend.jp/log_management/article/84-0008",
        "source_query" => "吸えログ 比較"
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:repair_action_candidate_target_urls"].invoke
    end

    assert_includes output, "mode=dry_run"
    assert_equal "https://it-trend.jp/log_management/article/84-0008", candidate.reload.metadata["target_url"]
    assert_includes output, "external_target_found="
    assert_includes output, "moved_to_reference="
    assert_includes output, "own_target_reassigned="
    assert_includes output, "planned_url_assigned="
    assert_includes output, "unresolved="
    assert_includes output, "invalid_target="
    assert_includes output, "rejected_irrelevant="
    assert_includes output, "candidate_ids="
  ensure
    ENV.delete("APPLY")
  end

  test "repair task applies external target url repair" do
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "外部URL修復適用対象",
      action_type: "seo_improvement",
      generation_source: "business_analyzer",
      immediate_value_yen: 10_000,
      success_probability: 0.5,
      expected_hours: 1,
      metadata: {
        "target_url" => "https://s.tabelog.com/rstLst/cond13-00-01/",
        "source_query" => "喫煙可能 飲食店"
      }
    )
    candidate.update_columns(
      metadata: {
        "target_url" => "https://s.tabelog.com/rstLst/cond13-00-01/",
        "source_query" => "喫煙可能 飲食店"
      }
    )

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:repair_action_candidate_target_urls"].reenable
    output, = capture_io do
      Rake::Task["aicoo:repair_action_candidate_target_urls"].invoke
    end

    metadata = candidate.reload.metadata
    assert_includes output, "mode=apply"
    assert_nil metadata["target_url"]
    assert_equal "external_reference", metadata["target_url_type"]
    assert_equal "external_reference", metadata["url_classification"]
    assert_includes metadata["reference_urls"], "https://s.tabelog.com/rstLst/cond13-00-01/"
    assert_includes metadata["competitor_urls"], "https://s.tabelog.com/rstLst/cond13-00-01/"
    assert_equal "rejected", candidate.status
  ensure
    ENV.delete("APPLY")
  end
end
