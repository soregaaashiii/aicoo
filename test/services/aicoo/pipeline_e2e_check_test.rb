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
        success_probability: 0.7
      )
      AutoRevisionTask.from_action_candidate(candidate)
      run = Aicoo::PipelineEngine.new(item).call

      result = PipelineE2eCheck.new(run).call

      assert result.pass?, result.checks.map { |check| "#{check.key}:#{check.status}:#{check.message}" }.join("\n")
      assert result.checks.all? { |check| check.status == "pass" }
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
  end
end
