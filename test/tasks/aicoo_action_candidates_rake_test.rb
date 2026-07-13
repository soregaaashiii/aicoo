require "test_helper"
require "rake"

class AicooActionCandidatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
    Rake::Task["aicoo:deduplicate_action_candidates"].reenable
  end

  test "deduplicate task runs in dry run mode without changing records" do
    first, second = create_duplicate_candidates

    output, = capture_io do
      Rake::Task["aicoo:deduplicate_action_candidates"].invoke
    end

    assert_includes output, "mode=dry_run"
    assert_includes output, "checked="
    assert_includes output, "duplicates="
    assert_equal "idea", first.reload.status
    assert_equal "idea", second.reload.status
  ensure
    ENV.delete("APPLY")
  end

  test "deduplicate task applies duplicate archive" do
    first, second = create_duplicate_candidates(first_value: 10_000, second_value: 30_000)

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:deduplicate_action_candidates"].reenable
    output, = capture_io do
      Rake::Task["aicoo:deduplicate_action_candidates"].invoke
    end

    assert_includes output, "mode=apply"
    assert_equal "archived", first.reload.status
    assert_equal "idea", second.reload.status
  ensure
    ENV.delete("APPLY")
  end

  private

  def create_duplicate_candidates(first_value: 10_000, second_value: 20_000)
    business = businesses(:suelog)
    [
      create_candidate(business:, value: first_value),
      create_candidate(business:, value: second_value)
    ]
  end

  def create_candidate(business:, value:)
    ActionCandidate.create!(
      business:,
      title: "吸えログ比較記事を1本作成する",
      description: "検索需要に対応する記事を作る",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      department: "revenue",
      status: "idea",
      immediate_value_yen: value,
      success_probability: 0.4,
      expected_hours: 2,
      metadata: {
        "opportunity_key" => "gsc:query:suelog-comparison",
        "source_query" => "吸えログ 比較",
        "concrete_task" => "吸えログ比較記事を1本作成する",
        "execution_mode" => "content_creation"
      }
    )
  end
end
