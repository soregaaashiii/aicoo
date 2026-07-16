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

  test "cleanup task skips already rejected irrelevant target repairs" do
    candidate = create_candidate!(
      title: "修復済み外部URL候補",
      status: "rejected",
      metadata: {
        "url_classification" => "external_reference",
        "target_url_type" => "external_reference",
        "repair_reason" => "external_reference",
        "rejection_reason" => "external_reference_target_url",
        "target_url_repair" => {
          "after_status" => "rejected"
        }
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "rejected_irrelevant=0"
    assert_includes output, "skipped_already_rejected_irrelevant=1"
    assert_match(/candidate_ids=\s*$/, output)
    assert_equal "rejected", candidate.reload.status
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task rejects irrelevant it trend evidence even without target url" do
    candidate = create_candidate!(
      title: "「吸えログ 比較」 / https://it-trend.jp/log_management/article/84-0008」向けの記事を1本作成する",
      action_type: "new_article_candidate",
      metadata: {
        "target_url" => nil,
        "planned_url" => "/articles/suelog-vs-it-trend",
        "url_classification" => "proposed_new",
        "reference_urls" => [ "https://it-trend.jp/log_management/article/84-0008" ],
        "article_plan" => { "title" => "ログ管理システム比較" }
      }
    )

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "rejected_irrelevant=1"
    assert_equal "rejected", candidate.reload.status
    assert_equal "irrelevant_external_evidence", candidate.metadata["rejection_reason"]
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task normalizes non article measurement candidate with article planned url" do
    candidate = create_candidate!(
      title: "CTAの計測設定を確認する",
      action_type: "other",
      metadata: {
        "planned_url" => "/articles/cv",
        "action_plan" => {
          "summary" => "CTAの計測設定を確認する",
          "target" => "/articles/cv"
        }
      }
    )

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    candidate.reload
    assert_includes output, "normalized_url_mismatch=1"
    assert_nil candidate.metadata["planned_url"]
    assert_equal "metadata_normalized", candidate.metadata["ranking_cleanup_status"]
    assert_equal "action_type_url_mismatch", candidate.metadata["ranking_cleanup_reason"]
    assert_equal "idea", candidate.status
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task moves metric path into target metrics" do
    candidate = create_candidate!(
      title: "電話・地図・アフィリエイト導線を5ページに追加する",
      action_type: "ui_improvement",
      metadata: {
        "target_url" => "/map/affiliate_clicks",
        "action_plan" => {
          "summary" => "電話・地図・アフィリエイト導線を5ページに追加する",
          "target" => "/map/affiliate_clicks"
        }
      }
    )

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    candidate.reload
    assert_includes output, "normalized_url_mismatch=1"
    assert_nil candidate.metadata["target_url"]
    assert_includes candidate.metadata["target_metrics"], "affiliate_clicks"
    assert_equal "metric_name_used_as_url", candidate.metadata["ranking_cleanup_reason"]
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task resolves daily run incident when step succeeded after candidate" do
    candidate = create_candidate!(
      title: "Daily Runが insight_generation で継続停止",
      action_type: "other",
      metadata: {
        "step_name" => "insight_generation",
        "daily_run_incident" => {
          "step_name" => "insight_generation",
          "started_at" => 3.hours.ago.iso8601
        }
      }
    )
    create_successful_daily_run_step!("insight_generation", started_at: 20.minutes.ago)

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "daily_run_candidates_checked=1"
    assert_includes output, "daily_run_latest_success_found=1"
    assert_includes output, "resolved=1"
    assert_includes output, "resolved_candidate_ids=#{candidate.id}"
    assert_equal "resolved", candidate.reload.status
    assert_equal "resolved", candidate.metadata["ranking_cleanup_status"]
    assert_equal "daily_run_step_recently_succeeded", candidate.metadata["ranking_cleanup_reason"]
    assert_equal "insight_generation", candidate.metadata.dig("daily_run_recovery_diagnosis", "step_name")

    ENV.delete("APPLY")
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    second_output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes second_output, "resolved=0"
    assert_includes second_output, "skipped_already_resolved_daily_run=1"
    assert_match(/candidate_ids=\s*$/, second_output)
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task resolves title only daily run incident and normalizes metadata" do
    candidate = create_candidate!(
      title: "Daily Runがinsight_generationで継続停止",
      action_type: "other",
      metadata: {}
    )
    step = create_successful_daily_run_step!("insight_generation", started_at: 20.minutes.ago)

    ENV["APPLY"] = "1"
    Rake::Task["aicoo:cleanup_action_expected_value_ranking"].reenable
    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    metadata = candidate.reload.metadata
    assert_includes output, "title_like_daily_run_candidate_id=#{candidate.id}"
    assert_includes output, "daily_run_candidate_id=#{candidate.id}"
    assert_includes output, "daily_run_candidates_checked=1"
    assert_includes output, "daily_run_latest_success_found=1"
    assert_includes output, "resolved=1"
    assert_equal "resolved", candidate.status
    assert_equal "daily_run_issue", metadata["source_type"]
    assert_equal "insight_generation", metadata["step_name"]
    assert_equal "stuck", metadata["incident_type"]
    assert_equal step.aicoo_daily_run_id, metadata["latest_run_id"]
    assert_equal "insight_generation", metadata.dig("daily_run_incident", "step_name")
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task keeps daily run incident unresolved without later successful step" do
    candidate = create_candidate!(
      title: "Daily Runが business_metrics_import で継続停止",
      action_type: "other",
      metadata: {
        "step_name" => "business_metrics_import",
        "daily_run_incident" => {
          "step_name" => "business_metrics_import",
          "started_at" => 1.hour.ago.iso8601
        }
      }
    )
    create_failed_daily_run_step!("business_metrics_import", started_at: 20.minutes.ago)

    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "daily_run_candidates_checked=1"
    assert_includes output, "daily_run_latest_success_found=0"
    assert_includes output, "daily_run_still_failing=1"
    assert_includes output, "unresolved_daily_run_candidate_ids=#{candidate.id}"
    assert_equal "idea", candidate.reload.status
  ensure
    ENV.delete("APPLY")
  end

  test "cleanup task does not count seo or integrated decision candidates as daily run incidents" do
    seo = create_candidate!(
      title: "insight_generationに関連するSEO改善",
      action_type: "seo_improvement",
      generation_source: "integrated_decision",
      metadata: {
        "concrete_task" => "insight_generationの結果を参考に記事を改善する"
      }
    )
    create_successful_daily_run_step!("insight_generation", started_at: 20.minutes.ago)

    output, = capture_io do
      Rake::Task["aicoo:cleanup_action_expected_value_ranking"].invoke
    end

    assert_includes output, "daily_run_candidates_checked=0"
    assert_not_includes output, "daily_run_candidate_id=#{seo.id}"
    assert_equal "idea", seo.reload.status
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

  def create_successful_daily_run_step!(step_name, started_at:)
    run = AicooDailyRun.create!(
      target_date: started_at.to_date,
      status: "partial_failed",
      source: "cron",
      started_at:,
      finished_at: started_at + 10.minutes
    )
    run.aicoo_daily_run_steps.create!(
      step_name:,
      status: "success",
      started_at:,
      finished_at: started_at + 10.minutes
    )
  end

  def create_failed_daily_run_step!(step_name, started_at:)
    run = AicooDailyRun.create!(
      target_date: started_at.to_date,
      status: "partial_failed",
      source: "cron",
      started_at:,
      finished_at: started_at + 10.minutes
    )
    run.aicoo_daily_run_steps.create!(
      step_name:,
      status: "failed",
      started_at:,
      finished_at: started_at + 10.minutes,
      error_message: "#{step_name} failed"
    )
  end
end
