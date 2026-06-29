require "test_helper"

module Aicoo
  class PipelineEngineTest < ActiveSupport::TestCase
    test "syncs all stage states for an idea pipeline item" do
      item = create_item
      IdeaPipeline::IdeaScorer.new(item).call

      run = PipelineEngine.new(item.reload).call

      assert_equal "idea_pipeline", run.pipeline_type
      assert_equal item, run.idea_pipeline_item
      assert_equal AicooPipelineRun::STAGES.sort, run.stage_states.keys.sort
      assert_equal "done", run.stage_state("discovery")["status"]
      assert_includes AicooPipelineRun::STATUSES, run.status
      assert run.gate_snapshot["serp"].present?
      assert run.retry_schedule["retryable_stages"].include?("serp")
      assert run.budget_snapshot.key?("over_budget")
      assert run.metadata["pivot"].present?
    end

    test "low score skips serp and keeps lp open" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 40)
      IdeaPipeline::SerpEvaluator.new(item).call

      run = PipelineEngine.new(item.reload).call

      assert_equal "skipped", run.stage_state("serp")["status"]
      assert_equal "score_below_serp_threshold", run.stage_state("serp")["reason"]
      assert_equal "open", run.stage_state("lp")["status"]
    end

    test "published lp waits for measure window" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 70)
      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      landing_page.update!(
        public_status: "published",
        status: "published",
        published_slug: "pipeline-wait-test",
        published_at: 1.day.ago
      )

      run = PipelineEngine.new(item.reload).call

      assert_equal "waiting", run.stage_state("measure")["status"]
      assert_equal "published_sample_window", run.waiting_reason
      assert run.waiting_until.present?
    end

    test "budget gate blocks when projected cost exceeds monthly budget" do
      profile = DataSourceCostProfile.find_or_initialize_by(source_key: "serp")
      profile.update!(
        source_key: "serp",
        name: "SERP",
        execution_mode: "manual",
        monthly_budget_yen: 100,
        monthly_spend_yen: 90,
        average_cost_yen: 20
      )
      item = create_item
      item.update!(status: "owner_approved", final_score: 70)

      run = PipelineEngine.new(item).call

      assert_equal "budget_blocked", run.status
      assert_equal "monthly_budget_exceeded", run.halted_reason
      assert_equal true, run.budget_snapshot["over_budget"]
    end

    test "mvp and publication create business and pipeline links" do
      item = create_item
      item.update!(status: "owner_approved", final_score: 80)
      landing_page = IdeaPipeline::LandingPageBuilder.new(item).call
      IdeaPipeline::Publisher.new(item).call
      IdeaPipeline::MvpSpecBuilder.new(item.reload).call

      run = PipelineEngine.new(item.reload).call

      assert item.business
      assert_equal item.business, landing_page.reload.business
      assert_equal item.business, run.business
      assert_equal landing_page, run.aicoo_lab_landing_page
      assert run.stage_state("publish")["status"].in?(%w[done])
      assert run.metadata["pivot"]["decision"].present?
    end

    private

    def create_item
      IdeaPipelineItem.create!(
        title: "Pipeline Engine Idea",
        short_description: "Pipeline Engine検証",
        problem: "状態遷移が分散している",
        target_user: "事業オーナー",
        revenue_model: "月額",
        mvp_concept: "LPで反応を見る",
        lp_concept: "ベネフィット訴求",
        difficulty_score: 20,
        development_hours: 4,
        ai_implementation_score: 80
      )
    end
  end
end
