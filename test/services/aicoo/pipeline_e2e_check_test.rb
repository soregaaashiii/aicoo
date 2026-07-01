require "test_helper"

module Aicoo
  class PipelineE2eCheckTest < ActiveSupport::TestCase
    setup do
      @previous_ga4_id = ENV["GA4_MEASUREMENT_ID"]
      ENV["GA4_MEASUREMENT_ID"] = "G-TEST"
      DataSourceCostProfile.find_or_create_by!(source_key: "serp") do |profile|
        profile.name = "SERP"
        profile.execution_mode = "manual"
      end.update!(api_key: "serper-key")
    end

    teardown do
      ENV["GA4_MEASUREMENT_ID"] = @previous_ga4_id
    end

    test "passes when idea business lp measurement and queues are linked" do
      item = create_published_pipeline_item
      candidate = item.business.action_candidates.create!(
        title: "LP改善",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.7,
        execution_prompt: "LPのCTAを改善してください。"
      )
      task = AutoRevisionTask.from_action_candidate(candidate)
      create_successful_daily_run!(candidate:, task:)
      create_activity_log!(business: item.business)
      create_score_snapshot!(candidate:)
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call

      assert result.pass?, result.checks.map { |check| "#{check.key}:#{check.status}:#{check.message}" }.join("\n")
      assert result.checks.all? { |check| check.status == "pass" }
      assert result.auto_revision_loop_checks.all? { |check| check.status == "pass" }
    end

    test "shows auto revision loop stop point when queue setting is disabled" do
      AicooAutoRevisionSetting.current.update!(enabled: false)
      item = create_published_pipeline_item
      candidate = item.business.action_candidates.create!(
        title: "LP改善",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.7,
        execution_prompt: "LPのCTAを改善してください。"
      )
      create_successful_daily_run!(candidate:, task: nil)
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call
      setting_check = result.auto_revision_loop_checks.find { |check| check.key == "loop_auto_revision_setting" }

      assert result.warning?
      assert_equal "warning", setting_check.status
      assert_equal setting_check, result.auto_revision_stop_point
      assert_includes setting_check.message, "AutoRevision QueueがOFF"
    end

    test "detects and repairs missing business and landing page link" do
      item = create_published_pipeline_item
      landing_page = item.aicoo_lab_landing_page
      business = item.business
      item.update!(business: nil)
      business.destroy!
      item.reload
      landing_page.reload
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call

      assert result.fail?
      assert result.checks.any? { |check| check.key == "business_created" && check.repair_action == "create_business" }

      repaired = PipelineE2eCheck.repair!(pipeline_run: run, action: "create_business")

      assert repaired.business
      assert_equal repaired.business, item.reload.business
      assert_equal repaired.business, landing_page.reload.business
      assert_includes Business.real_businesses, repaired.business
    end

    test "repairs disabled daily run and serp flags" do
      item = create_published_pipeline_item
      business = item.business
      business.update!(daily_run_enabled: false, serp_enabled: false)
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call

      assert result.checks.any? { |check| check.key == "daily_run" && check.status == "fail" }
      assert result.checks.any? { |check| check.key == "serp" && check.status == "fail" }

      PipelineE2eCheck.repair!(pipeline_run: run, action: "enable_daily_run")
      PipelineE2eCheck.repair!(pipeline_run: run, action: "enable_serp")

      assert business.reload.daily_run_enabled?
      assert business.serp_enabled?
    end

    test "treats missing serp key as warning because serp is optional" do
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: nil)
      item = create_published_pipeline_item
      candidate = item.business.action_candidates.create!(
        title: "LP改善",
        status: "approved",
        action_type: "seo_improvement",
        immediate_value_yen: 10_000,
        success_probability: 0.7
      )
      AutoRevisionTask.from_action_candidate(candidate)
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call
      serp_check = result.checks.find { |check| check.key == "missing_serp_key" }

      assert result.warning?
      assert_equal "warning", serp_check.status
      assert_equal "serp_optional_missing", serp_check.details.fetch(:reason)
      assert_includes serp_check.message, "既存データによる改善ループは継続します"
    end

    test "analytics import exclusion does not hide normal aicoo generated business" do
      Business.create!(name: "AICOO Analytics Import", status: "launched")
      item = create_published_pipeline_item

      assert_includes Business.real_businesses, item.business
      assert_not_includes Business.real_businesses, Business.find_by!(name: "AICOO Analytics Import")
    end

    private

    def create_published_pipeline_item
      item = IdeaPipelineItem.create!(
        title: "E2Eチェック事業",
        short_description: "E2Eを確認する公開LP",
        problem: "公開後の事業化が途切れる",
        target_user: "Owner",
        revenue_model: "送客",
        mvp_concept: "LP",
        lp_concept: "E2E確認LP",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80,
        status: "owner_approved",
        final_score: 75,
        evaluated_at: 1.hour.ago
      )
      Aicoo::IdeaPipeline::LandingPageBuilder.new(item).call
      Aicoo::IdeaPipeline::Publisher.new(item).call
      item.reload
    end

    def create_successful_daily_run!(candidate:, task:)
      daily_run = AicooDailyRun.create!(
        target_date: Date.yesterday,
        status: "success",
        source: "cron",
        started_at: 10.minutes.ago,
        finished_at: 8.minutes.ago,
        action_candidates_generated_count: 1,
        analytics_fetch_count: 1
      )
      daily_run.aicoo_daily_run_steps.create!(
        step_name: "analytics_fetch",
        status: "success",
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        metadata: { success_count: 1 }
      )
      daily_run.aicoo_daily_run_steps.create!(
        step_name: "action_generation",
        status: "success",
        started_at: 9.minutes.ago,
        finished_at: 8.minutes.ago,
        metadata: { created_count: 1 }
      )
      return daily_run unless task

      AicooAutoRevisionSetting.current.update!(enabled: true)
      AutoRevisionQueueRun.create!(
        aicoo_daily_run: daily_run,
        generated_tasks_count: 1,
        skipped_candidates_count: 0,
        high_risk_candidates_count: 0,
        executed_at: 7.minutes.ago,
        metadata: {
          "reason" => "created_tasks",
          "message" => "AutoRevisionTaskを1件生成しました。",
          "created_task_ids" => [ task.id ],
          "candidate_count" => 1
        }
      )
      daily_run.aicoo_daily_run_steps.create!(
        step_name: "auto_revision_queue",
        status: "success",
        started_at: 8.minutes.ago,
        finished_at: 7.minutes.ago,
        metadata: { generated_tasks_count: 1 }
      )
      daily_run
    end

    def create_activity_log!(business:)
      business.business_activity_logs.create!(
        activity_type: "lp_updated",
        resource_type: "LandingPage",
        resource_id: "lp-test",
        source_app: "aicoo",
        source_method: "logger",
        title: "LPを改善",
        occurred_at: Time.current,
        detected_at: Time.current,
        idempotency_key: "pipeline-e2e-lp-updated-#{business.id}",
        diff_summary: "CTAを改善"
      )
    end

    def create_score_snapshot!(candidate:)
      candidate.action_candidate_score_snapshots.create!(
        business: candidate.business,
        recorded_on: Date.current,
        raw_rank: 1,
        adjusted_rank: 1,
        rank_delta: 0,
        raw_score: candidate.final_score || 1,
        judge_adjusted_score: candidate.final_score || 1,
        reason: "E2E learning snapshot"
      )
    end
  end
end
