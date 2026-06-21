require "test_helper"

module Admin
  module AicooLab
    class ReviewQueueControllerTest < ActionDispatch::IntegrationTest
      test "shows preview ready experiments" do
        experiment = create_review_experiment(title: "Review visible")

        get admin_aicoo_lab_review_queue_url

        assert_response :success
        assert_includes response.body, experiment.title
        assert_includes response.body, "レビュー待ち"
        assert_includes response.body, "承認しても本番公開や課金は発生しません"
        assert_includes response.body, "LPプレビューを見る"
      end

      test "lists experiments by lab priority score" do
        low = create_review_experiment(title: "Low review", expected_90d_profit_yen: 1_000, success_probability: 0.1, estimated_work_minutes: 120, experiment_type: "seo")
        high = create_review_experiment(title: "High review", expected_90d_profit_yen: 100_000, success_probability: 0.5, estimated_work_minutes: 15, experiment_type: "lp")

        get admin_aicoo_lab_review_queue_url

        assert_response :success
        assert_operator response.body.index(high.title), :<, response.body.index(low.title)
      end

      test "bulk moves selected experiments to approval pending" do
        first_experiment = create_review_experiment(title: "Pending bulk 1")
        second_experiment = create_review_experiment(title: "Pending bulk 2")

        post admin_aicoo_lab_review_queue_bulk_update_url,
             params: { bulk_action: "approval_pending", experiment_ids: [ first_experiment.id, second_experiment.id ] }

        assert_redirected_to admin_aicoo_lab_review_queue_url
        assert_equal "approval_pending", first_experiment.reload.status
        assert_equal "pending", first_experiment.approval_status
        assert_equal "approval_pending", second_experiment.reload.status
        assert_equal "pending", second_experiment.approval_status
      end

      test "bulk approves selected experiments" do
        experiment = create_review_experiment(title: "Approve bulk")

        post admin_aicoo_lab_review_queue_bulk_update_url,
             params: { bulk_action: "approve", experiment_ids: [ experiment.id ] }

        assert_redirected_to admin_aicoo_lab_review_queue_url
        assert_equal "approved", experiment.reload.approval_status
      end

      test "bulk rejects selected experiments" do
        experiment = create_review_experiment(title: "Reject bulk")

        post admin_aicoo_lab_review_queue_bulk_update_url,
             params: { bulk_action: "reject", experiment_ids: [ experiment.id ] }

        assert_redirected_to admin_aicoo_lab_review_queue_url
        assert_equal "rejected", experiment.reload.approval_status
      end

      test "fast review approves and rejects" do
        approve_experiment = create_review_experiment(title: "Fast approve")
        reject_experiment = create_review_experiment(title: "Fast reject")

        patch admin_aicoo_lab_review_queue_approve_url(approve_experiment)
        assert_equal "approved", approve_experiment.reload.approval_status

        patch admin_aicoo_lab_review_queue_reject_url(reject_experiment)
        assert_equal "rejected", reject_experiment.reload.approval_status
      end

      private

      def create_review_experiment(attributes = {})
        experiment = AicooLabExperiment.create!(
          {
            title: "Review experiment",
            description: "Review experiment description",
            experiment_type: "lp",
            market_category: "review market",
            acquisition_channel: "seo",
            status: "preview_ready",
            approval_status: "not_required",
            expected_90d_profit_yen: 50_000,
            success_probability: 0.3,
            budget_yen: 0,
            estimated_work_minutes: 60,
            learning_value_score: 1.0
          }.merge(attributes)
        )
        experiment.create_aicoo_lab_landing_page!(
          headline: "#{experiment.title} headline",
          subheadline: "Review subheadline",
          body: "Review body",
          cta_text: "事前登録する",
          status: "preview_ready",
          generation_source: "candidate_conversion"
        )
        experiment
      end
    end
  end
end
