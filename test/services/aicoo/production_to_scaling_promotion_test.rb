require "test_helper"

module Aicoo
  class ProductionToScalingPromotionTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.update!(created_by_aicoo: true, lifecycle_stage: "production", status: "launched", launched: true)
      @business.business_services.create!(
        name: "Suelog Production",
        status: "production",
        url: "https://suelog.example.com",
        metadata: {
          paid_users: 8,
          active_users: 20,
          registrations: 30,
          retention_rate: "0.7",
          churn_count: 1,
          cac_hypothesis_yen: 8_000,
          ltv_hypothesis_yen: 80_000,
          primary_channel: "SEO"
        }
      )
      @business.revenue_events.create!(event_type: "revenue", amount: 160_000, occurred_on: Date.current)
      @business.revenue_events.create!(event_type: "expense", amount: 20_000, occurred_on: Date.current)
      @business.business_metric_dailies.create!(recorded_on: Date.current, users: 20, sessions: 100, conversions: 8, impressions: 2_000)
      @business.action_candidates.create!(title: "SEOを伸ばす", action_type: "seo_improvement", status: "approved")
    end

    test "scaling evaluation summary classifies strong production business" do
      summary = Aicoo::ScalingEvaluationSummary.for_business(@business)

      assert_equal 160_000, summary.monthly_revenue_yen
      assert_equal 8, summary.paid_users
      assert_equal 140_000, summary.gross_profit_yen
      assert_equal "strong", summary.verdict
      assert_equal "SEO", summary.recommended_investment
      assert summary.promotable?
    end

    test "scaling ready check exposes pass state" do
      result = Aicoo::ScalingReadyCheck.new(@business).call

      assert result.checks.find { |check| check.key == :production_stage }.passed
      assert result.checks.find { |check| check.key == :cac }.passed
      assert result.checks.find { |check| check.key == :ltv }.passed
    end

    test "promotion updates lifecycle and creates task and timeline activity" do
      assert_difference -> { ActionCandidate.count }, 1 do
        assert_difference -> { AutoRevisionTask.count }, 1 do
          assert_difference -> { BusinessActivityLog.where(activity_type: "scaling_promoted").count }, 1 do
            Aicoo::ScalingPromotion.new(business: @business).call
          end
        end
      end

      assert_equal "scaling", @business.reload.lifecycle_stage
      task = AutoRevisionTask.last
      assert_equal "waiting_approval", task.status
      assert_includes task.execution_prompt, "現在の勝ち筋"
      assert_includes task.execution_prompt, "7日後に見る指標"
      assert_includes task.execution_prompt, "30日後に見る指標"
    end
  end
end
