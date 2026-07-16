require "test_helper"
require "rake"

class AicooActionRankingCleanupRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:cleanup_action_expected_value_ranking")
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
  end

  test "cleanup task runs in dry run without changing external candidate" do
    candidate = create_candidate!(
      title: "外部URL由来候補",
      metadata: {
        "url_classification" => "external_reference",
        "target_url" => "https://it-trend.jp/log_management/article/84-0008"
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "mode=dry_run"
    assert_includes output, "rejected_irrelevant="
    assert_equal "idea", candidate.reload.status
    assert_nil candidate.metadata["ranking_cleanup_status"]
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task marks duplicate article candidates as rejected_duplicate" do
    representative = create_candidate!(
      title: "「吸えログ 比較」向けの記事を1本作成する",
      immediate_value_yen: 30_000,
      action_type: "new_article_candidate",
      metadata: duplicate_article_metadata
    )
    duplicate = create_candidate!(
      title: "吸えログ 比較の記事を作成する",
      immediate_value_yen: 10_000,
      action_type: "article_create",
      metadata: duplicate_article_metadata
    )

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "mode=apply"
    assert_equal "idea", representative.reload.status
    assert_equal "rejected_duplicate", duplicate.reload.status
    assert_equal representative.id, duplicate.metadata["representative_action_candidate_id"]
    assert_equal "duplicate_action_candidate", duplicate.metadata["ranking_cleanup_reason"]
    assert_includes representative.metadata["source_candidate_ids"], representative.id
    assert_includes representative.metadata["source_candidate_ids"], duplicate.id
  ensure
    ENV.delete("APPLY")
  end

  private

  def create_candidate!(attributes = {})
    ActionCandidate.create!(
      {
        business: businesses(:suelog),
        title: "施策候補",
        action_type: "seo_improvement",
        generation_source: "business_analyzer",
        status: "idea",
        immediate_value_yen: 10_000,
        success_probability: 0.5,
        expected_hours: 1,
        metadata: {}
      }.merge(attributes)
    )
  end

  def duplicate_article_metadata
    {
      "query" => "吸えログ 比較",
      "planned_url" => "/articles/suelog-vs-tabelog",
      "work_type" => "new_article",
      "url_classification" => "proposed_new"
    }
  end
end
