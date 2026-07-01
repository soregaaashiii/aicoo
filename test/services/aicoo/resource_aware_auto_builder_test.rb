require "test_helper"

module Aicoo
  class ResourceAwareAutoBuilderTest < ActiveSupport::TestCase
    setup do
      AutoBuildTask.delete_all
      AutoRevisionTask.delete_all
      ActionCandidate.delete_all
      AicooResourceBudget.delete_all
      @business = Business.create!(
        name: "Auto Build Test",
        description: "未知市場向けのLP検証Business",
        status: "launched",
        lifecycle_stage: "lp_validation",
        created_by_aicoo: true,
        auto_build_enabled: true,
        auto_build_requires_approval: true,
        auto_build_risk_level: "low"
      )
      @landing_page = create_landing_page!(@business)
    end

    test "skips when global auto build is disabled" do
      budget = AicooResourceBudget.create!(auto_build_enabled: false)

      result = ResourceAwareAutoBuilder.new(budget:).call

      assert_equal 0, result.created_count
      assert_includes result.skipped.first, "auto_build_enabled=false"
    end

    test "creates auto build task and auto revision prompt when resources are available" do
      create_lp_reaction!(pv: 1, cta_clicks: 3, signups: 0)
      budget = available_budget

      assert_difference("AutoBuildTask.count", 1) do
        assert_difference("AutoRevisionTask.count", 1) do
          assert_difference("ActionCandidate.count", 1) do
            @result = ResourceAwareAutoBuilder.new(budget:).call
          end
        end
      end

      task = AutoBuildTask.last
      assert_equal @business, task.business
      assert_equal "pending", task.status
      assert_equal "priority_b", task.build_strategy
      assert task.codex_prompt.include?("MVP開発フェーズ")
      assert_equal task.auto_revision_task, AutoRevisionTask.last
      assert_equal "waiting_approval", task.auto_revision_task.status
      assert_equal true, task.metadata.fetch("resource_aware_auto_builder")
      assert_equal 1, @result.created_count
    end

    test "uses learning value to build low reaction priority c candidates" do
      create_lp_reaction!(pv: 1, cta_clicks: 0, signups: 0)
      @business.update!(category: nil)

      result = ResourceAwareAutoBuilder.new(budget: available_budget).call

      task = result.created_tasks.first
      assert_equal "priority_c", task.build_strategy
      assert task.learning_value_score >= 70
    end

    test "does not duplicate active auto build task" do
      create_lp_reaction!(pv: 120, cta_clicks: 4, signups: 1)
      AutoBuildTask.create!(
        business: @business,
        status: "pending",
        build_strategy: "priority_b",
        risk_level: "low"
      )

      result = ResourceAwareAutoBuilder.new(budget: available_budget).call

      assert_equal 0, result.created_count
      assert_includes result.skipped.first, "active_auto_build_task_exists"
    end

    private

    def available_budget
      AicooResourceBudget.create!(
        auto_build_enabled: true,
        monthly_ai_budget_yen: 10_000,
        current_month_ai_spend_yen: 0,
        codex_concurrent_limit: 2,
        codex_waiting_limit: 10,
        build_queue_limit: 10,
        deploy_queue_limit: 10,
        render_service_limit: 0,
        simultaneous_mvp_limit: 10
      )
    end

    def create_landing_page!(business)
      experiment = AicooLabExperiment.create!(
        title: "Auto Build Experiment",
        experiment_type: "lp",
        acquisition_channel: "seo",
        market_category: "unknown",
        status: "running"
      )
      AicooLabLandingPage.create!(
        aicoo_lab_experiment: experiment,
        business:,
        headline: "公開LP",
        subheadline: "反応を見るLP",
        body: "本文",
        cta_text: "登録する",
        preview_slug: "auto-build-#{SecureRandom.hex(4)}",
        published_slug: "auto-build-public-#{SecureRandom.hex(4)}",
        status: "published",
        public_status: "published",
        published_at: Time.current
      )
    end

    def create_lp_reaction!(pv:, cta_clicks:, signups:)
      pv.times { create_event!("view") }
      cta_clicks.times { create_event!("cta_click") }
      signups.times do |index|
        @landing_page.aicoo_lab_signups.create!(email: "test#{index}@example.com")
      end
    end

    def create_event!(event_type)
      @landing_page.aicoo_lab_landing_page_events.create!(
        event_type:,
        occurred_at: Time.current
      )
    end
  end
end
