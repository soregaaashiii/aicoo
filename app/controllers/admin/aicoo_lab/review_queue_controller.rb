module Admin
  module AicooLab
    class ReviewQueueController < ApplicationController
      before_action :set_experiment, only: %i[ show approval_pending approve reject paused ]

      def index
        @experiments = review_queue
      end

      def show
        @landing_page = @experiment.aicoo_lab_landing_page
        @next_experiment = next_experiment
      end

      def bulk_update
        experiments = AicooLabExperiment.where(id: selected_experiment_ids)
        experiments.find_each { |experiment| apply_action!(experiment, params[:bulk_action]) }

        redirect_to admin_aicoo_lab_review_queue_path, notice: "Updated #{experiments.size} experiments."
      end

      def approval_pending
        apply_action!(@experiment, "approval_pending")
        redirect_after_review("Experiment is waiting for approval.")
      end

      def approve
        apply_action!(@experiment, "approve")
        redirect_after_review("Experiment was approved.")
      end

      def reject
        apply_action!(@experiment, "reject")
        redirect_after_review("Experiment was rejected.")
      end

      def paused
        apply_action!(@experiment, "paused")
        redirect_after_review("Experiment was paused.")
      end

      private

      def review_queue
        AicooLabExperiment.includes(:aicoo_lab_landing_page).review_queue
      end

      def set_experiment
        @experiment = AicooLabExperiment.find(params.expect(:experiment_id))
      end

      def selected_experiment_ids
        Array(params[:experiment_ids]).compact_blank
      end

      def apply_action!(experiment, action)
        case action
        when "approval_pending"
          experiment.update!(status: "approval_pending", approval_status: "pending")
        when "approve"
          Aicoo::ApprovalService.approve(experiment, operator: "owner", source: "lab_review_queue")
        when "reject"
          Aicoo::ApprovalService.reject(experiment, operator: "owner", source: "lab_review_queue")
        when "paused"
          experiment.mark_status!("paused")
        end
      end

      def redirect_after_review(notice)
        if next_experiment
          redirect_to admin_aicoo_lab_review_queue_experiment_path(next_experiment), notice:
        else
          redirect_to admin_aicoo_lab_review_queue_path, notice:
        end
      end

      def next_experiment
        review_queue.where.not(id: @experiment.id).first
      end
    end
  end
end
