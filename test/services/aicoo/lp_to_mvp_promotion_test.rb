require "test_helper"

module Aicoo
  class LpToMvpPromotionTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.update!(created_by_aicoo: true, lifecycle_stage: "lp_validation")
      @landing_page = create_landing_page(@business)
      6.times { @landing_page.aicoo_lab_landing_page_events.create!(event_type: "view", occurred_at: Time.current) }
      3.times { @landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click", occurred_at: Time.current) }
      @landing_page.aicoo_lab_signups.create!(email: "mvp@example.com")
      @business.business_metric_dailies.create!(recorded_on: Date.current, clicks: 12, impressions: 500)
    end

    test "lp evaluation summary classifies promising landing page" do
      summary = Aicoo::LpEvaluationSummary.for_business(@business).first

      assert_equal 6, summary.pv
      assert_equal 3, summary.cta_clicks
      assert_equal 1, summary.cv
      assert_equal 12, summary.gsc_clicks
      assert_equal 500, summary.gsc_impressions
      assert_equal "strong", summary.verdict
      assert summary.promotable?
    end

    test "mvp ready check exposes missing and passed items" do
      result = Aicoo::MvpReadyCheck.new(@business).call

      assert result.checks.find { |check| check.key == :published_lp }.passed
      assert result.checks.find { |check| check.key == :conversion }.passed
      assert result.checks.find { |check| check.key == :repository }.passed
    end

    test "promotion updates lifecycle and creates service task and timeline activity" do
      assert_difference -> { BusinessService.count }, 1 do
        assert_difference -> { ActionCandidate.count }, 1 do
          assert_difference -> { AutoRevisionTask.count }, 1 do
            assert_difference -> { BusinessActivityLog.where(activity_type: "mvp_promoted").count }, 1 do
              Aicoo::MvpPromotion.new(business: @business, landing_page_id: @landing_page.id).call
            end
          end
        end
      end

      assert_equal "mvp", @business.reload.lifecycle_stage
      task = AutoRevisionTask.last
      assert_equal "waiting_approval", task.status
      assert_includes task.execution_prompt, "Business名:"
      assert_includes task.execution_prompt, @business.name
      assert_includes task.execution_prompt, "MVPで作らないもの"
    end

    private

    def create_landing_page(business)
      experiment = AicooLabExperiment.create!(
        title: "MVP Promotion LP",
        experiment_type: "lp",
        acquisition_channel: "seo",
        status: "running",
        approval_status: "approved",
        assumed_price_yen: 2_980
      )
      experiment.create_aicoo_lab_landing_page!(
        business:,
        headline: "請求前チェックリスト",
        subheadline: "フリーランスが請求漏れを防ぐサービス",
        body: "請求前に確認すべき項目を整理し、ミスを減らします。",
        cta_text: "事前登録する",
        status: "published",
        public_status: "published",
        published_slug: "mvp-promotion-lp",
        published_at: Time.current,
        assumed_price_yen: 2_980
      )
    end
  end
end
