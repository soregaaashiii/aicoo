require "test_helper"

module Aicoo
  class MvpToProductionPromotionTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.update!(created_by_aicoo: true, lifecycle_stage: "mvp", status: "building", launched: true)
      @service = @business.business_services.create!(
        name: "Suelog MVP",
        status: "live",
        url: "https://suelog.example.com",
        repository: "soregaaashiii/aicoo",
        deploy_target: "bin/deploy",
        stripe_account: "acct_test",
        metadata: {
          registrations: 12,
          active_users: 8,
          free_users: 9,
          paid_users: 3,
          churn_count: 1,
          retention_rate: "0.66",
          user_feedback: "継続利用したい"
        }
      )
      @business.revenue_events.create!(event_type: "revenue", amount: 45_000, occurred_on: Date.current)
      @business.business_metric_dailies.create!(recorded_on: Date.current, users: 8, sessions: 30, conversions: 4)
    end

    test "mvp evaluation summary classifies strong service" do
      summary = Aicoo::MvpEvaluationSummary.for_business(@business).first

      assert_equal @service, summary.business_service
      assert_equal 12, summary.registrations
      assert_equal 3, summary.paid_users
      assert_equal 45_000, summary.revenue_yen
      assert_equal "strong", summary.verdict
      assert summary.promotable?
    end

    test "production ready check exposes pass state" do
      result = Aicoo::ProductionReadyCheck.new(@business).call

      assert result.checks.find { |check| check.key == :service_url }.passed
      assert result.checks.find { |check| check.key == :stripe }.passed
      assert result.checks.find { |check| check.key == :feedback }.passed
    end

    test "promotion updates lifecycle service and creates task and timeline activity" do
      assert_difference -> { ActionCandidate.count }, 1 do
        assert_difference -> { AutoRevisionTask.count }, 1 do
          assert_difference -> { BusinessActivityLog.where(activity_type: "production_promoted").count }, 1 do
            Aicoo::ProductionPromotion.new(business: @business, business_service_id: @service.id).call
          end
        end
      end

      assert_equal "production", @business.reload.lifecycle_stage
      assert_equal "launched", @business.status
      assert @business.launched?
      assert_equal "production", @service.reload.status
      task = AutoRevisionTask.last
      assert_equal "waiting_approval", task.status
      assert_includes task.execution_prompt, "MVPの結果:"
      assert_includes task.execution_prompt, "課金導線"
      assert_includes task.execution_prompt, "最初に作らないもの"
    end
  end
end
