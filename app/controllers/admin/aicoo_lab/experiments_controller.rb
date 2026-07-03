module Admin
  module AicooLab
    class ExperimentsController < ApplicationController
      before_action :set_experiment, only: %i[
        show edit update destroy preview_ready approval_pending approve reject running paused success failed reevaluate recalculate_errors
        create_30d_results_from_metrics create_90d_results_from_metrics
      ]

      def index
        @experiments = filtered_experiments
      end

      def approvals
        @experiments = AicooLabExperiment.approval_pending
      end

      def show
        @prediction = @experiment.aicoo_lab_predictions.new
        @result = @experiment.aicoo_lab_results.new
        @landing_page = @experiment.aicoo_lab_landing_page
      end

      def new
        @experiment = AicooLabExperiment.new
      end

      def edit
      end

      def create
        @experiment = AicooLabExperiment.new(experiment_params)

        if @experiment.save
          redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Experiment was successfully created."
        else
          render :new, status: :unprocessable_content
        end
      end

      def update
        if @experiment.update(experiment_params)
          redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Experiment was successfully updated."
        else
          render :edit, status: :unprocessable_content
        end
      end

      def destroy
        @experiment.destroy!
        redirect_to admin_aicoo_lab_experiments_path, notice: "Experiment was successfully destroyed.", status: :see_other
      end

      def preview_ready
        @experiment.aicoo_lab_landing_page&.update!(status: "preview_ready")
        update_status("preview_ready")
      end

      def approval_pending
        @experiment.update!(status: "approval_pending", approval_status: "pending")
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Experiment is waiting for approval."
      end

      def approve
        result = Aicoo::ApprovalService.approve(@experiment, operator: "owner", source: "lab_experiment_detail")
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: result.message
      end

      def reject
        result = Aicoo::ApprovalService.reject(@experiment, operator: "owner", source: "lab_experiment_detail")
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: result.message
      end

      def running
        update_status("running")
      end

      def paused
        update_status("paused")
      end

      def success
        update_status("success")
      end

      def failed
        update_status("failed")
      end

      def reevaluate
        update_status("reevaluate")
      end

      def recalculate_errors
        @experiment.recalculate_error_metrics!
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Error metrics were recalculated."
      end

      def create_30d_results_from_metrics
        create_metric_results!(30)
      end

      def create_90d_results_from_metrics
        create_metric_results!(90)
      end

      private

      def set_experiment
        @experiment = AicooLabExperiment.find(params.expect(:id))
      end

      def filtered_experiments
        experiments = AicooLabExperiment.by_lab_priority
        experiments = experiments.where(status: params[:status]) if params[:status].present?
        experiments = experiments.where(approval_status: params[:approval_status]) if params[:approval_status].present?
        experiments = experiments.where(experiment_type: params[:experiment_type]) if params[:experiment_type].present?
        experiments = experiments.where(market_category: params[:market_category]) if params[:market_category].present?
        experiments = experiments.where(acquisition_channel: params[:acquisition_channel]) if params[:acquisition_channel].present?
        experiments
      end

      def update_status(status)
        @experiment.mark_status!(status)
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "Experiment status was updated to #{status}."
      end

      def create_metric_results!(target_days)
        landing_page = @experiment.aicoo_lab_landing_page
        if landing_page.blank?
          redirect_to admin_aicoo_lab_experiment_path(@experiment), alert: "Landing page is not created yet."
          return
        end

        MetricResultsCreator.new(@experiment, landing_page, target_days).call
        redirect_to admin_aicoo_lab_experiment_path(@experiment), notice: "#{target_days} day metric results were created."
      end

      def experiment_params
        params.expect(
          aicoo_lab_experiment: [
            :title, :description, :experiment_type, :market_category, :acquisition_channel, :status, :approval_status,
            :public_url, :preview_url, :expected_90d_profit_yen, :success_probability, :learning_value_score,
            :budget_yen, :actual_cost_yen, :estimated_work_minutes, :actual_work_minutes, :started_at, :published_at,
            :score_due_7d_at, :score_due_30d_at, :score_due_90d_at, :scored_7d_at, :scored_30d_at, :scored_90d_at,
            :sample_pv_threshold, :current_pv, :created_by, :notes, :lp_word_count, :cta_count, :assumed_price_yen,
            :development_minutes, :feature_count, :neglect_loss_90d_yen, :neglect_loss_reason
          ]
        )
      end

      MetricResultsCreator = Data.define(:experiment, :landing_page, :target_days) do
        def call
          experiment.aicoo_lab_results.create!(result_type: "pv", target_days:, actual_value: views, actual_value_unit: "count", sample_size: views)
          experiment.aicoo_lab_results.create!(result_type: "ctr", target_days:, actual_value: percent(landing_page.cta_rate), actual_value_unit: "percent", sample_size: views)
          experiment.aicoo_lab_results.create!(result_type: "conversion_rate", target_days:, actual_value: percent(landing_page.signup_rate), actual_value_unit: "percent", sample_size: views)
        end

        private

        def views
          landing_page.view_count
        end

        def percent(rate)
          return 0 if rate.blank?

          rate * 100
        end
      end
    end
  end
end
