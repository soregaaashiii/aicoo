module Admin
  module AicooLab
    class ApprovedExperimentsController < ApplicationController
      before_action :set_experiment, only: :running

      def index
        @experiments = approved_not_started
      end

      def running
        @experiment.mark_status!("running")
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Experiment was started."
      end

      def bulk_running
        experiments = approved_not_started.where(id: selected_experiment_ids)
        experiments.find_each { |experiment| experiment.mark_status!("running") }

        redirect_to admin_aicoo_lab_approved_experiments_path, notice: "Started #{experiments.size} experiments."
      end

      private

      def approved_not_started
        AicooLabExperiment.includes(:aicoo_lab_landing_page).approved_not_started
      end

      def set_experiment
        @experiment = approved_not_started.find(params.expect(:experiment_id))
      end

      def selected_experiment_ids
        Array(params[:experiment_ids]).compact_blank
      end
    end
  end
end
