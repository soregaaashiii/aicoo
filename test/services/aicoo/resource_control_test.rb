require "test_helper"

module Aicoo
  class ResourceControlTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      @business.update!(resource_status: "active")
    end

    test "resource summary calculates monthly load and snooze recommendation" do
      ActionCandidate.where(business: @business).delete_all
      @business.business_activity_logs.delete_all
      @business.revenue_events.delete_all

      summary = Aicoo::ResourceSummary.for_business(@business)

      assert summary.auto_snooze_recommended
      assert_includes summary.auto_snooze_reason, "Watch候補"
      assert_operator summary.monthly_cost_yen, :>=, 0
    end

    test "attention score rises with errors inquiries and candidates" do
      @business.action_candidates.create!(title: "確認が必要な改善", action_type: "seo_improvement", status: "approved")
      landing_page = create_landing_page(@business)
      landing_page.aicoo_lab_signups.create!(email: "attention@example.com")
      @business.business_activity_logs.create!(
        activity_type: "api_error",
        source_app: "aicoo",
        source_method: "logger",
        resource_type: "Business",
        resource_id: @business.id.to_s,
        title: "API失敗",
        occurred_at: Time.current,
        detected_at: Time.current,
        idempotency_key: "attention-error"
      )

      score = Aicoo::AttentionScore.for_business(@business)

      assert_operator score.score, :>, 0
      assert score.reasons.any? { |reason| reason.include?("エラー") }
      assert score.reasons.any? { |reason| reason.include?("問い合わせ") }
      assert score.reasons.any? { |reason| reason.include?("改善候補") }
    end

    test "resource status change records timeline activity" do
      assert_difference -> { BusinessActivityLog.where(activity_type: "resource_status_changed").count }, 1 do
        @business.change_resource_status!("watch", reason: "安定運用のため", operator: "owner")
      end

      assert_equal "watch", @business.reload.resource_status
      assert_equal "安定運用のため", @business.resource_status_reason
      assert @business.next_review_on.present?
    end

    private

    def create_landing_page(business)
      experiment = AicooLabExperiment.create!(
        title: "Resource LP",
        experiment_type: "lp",
        acquisition_channel: "seo",
        status: "running",
        approval_status: "approved"
      )
      experiment.create_aicoo_lab_landing_page!(
        business:,
        headline: "Resource LP",
        subheadline: "Resource",
        body: "Resource",
        cta_text: "登録",
        status: "published",
        public_status: "published",
        published_slug: "resource-lp",
        published_at: Time.current
      )
    end
  end
end
