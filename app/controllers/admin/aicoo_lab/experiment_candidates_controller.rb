module Admin
  module AicooLab
    class ExperimentCandidatesController < ApplicationController
      before_action :set_candidate,
                    only: %i[ show edit update destroy approve reject convert_to_experiment
                              convert_to_experiment_with_landing_page ]

      def index
        @summary = CandidateSummary.new
        @candidates = filtered_candidates
      end

      def show
      end

      def new
        @template_key = params[:template].presence || "low_cost_lp"
        @candidate = AicooLabExperimentCandidate.from_template(@template_key)
      end

      def edit
      end

      def create
        @candidate = AicooLabExperimentCandidate.new(candidate_params)

        if @candidate.save
          redirect_to admin_aicoo_lab_candidate_path(@candidate), notice: "Experiment candidate was successfully created."
        else
          render :new, status: :unprocessable_content
        end
      end

      def update
        if @candidate.update(candidate_params)
          redirect_to admin_aicoo_lab_candidate_path(@candidate), notice: "Experiment candidate was successfully updated."
        else
          render :edit, status: :unprocessable_content
        end
      end

      def destroy
        @candidate.destroy!
        redirect_to admin_aicoo_lab_candidates_path, notice: "Experiment candidate was successfully destroyed.", status: :see_other
      end

      def approve
        business = @candidate.approve!
        redirect_to business_path(business),
                    notice: helpers.safe_join([
                      "事業を作成しました。 ",
                      helpers.link_to("作成されたBusiness詳細へ", business_path(business))
                    ])
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_aicoo_lab_candidate_path(@candidate),
                    alert: "事業を作成できませんでした: #{e.record.errors.full_messages.to_sentence}"
      end

      def reject
        @candidate.reject!
        redirect_to admin_aicoo_lab_candidate_path(@candidate), notice: "Experiment candidate was rejected."
      end

      def convert_to_experiment
        experiment = @candidate.convert_to_experiment!
        redirect_to admin_aicoo_lab_experiment_path(experiment), notice: "Experiment candidate was converted."
      end

      def convert_to_experiment_with_landing_page
        experiment = AicooLabCandidateConverter.new([ @candidate ]).call.experiments.first
        redirect_to admin_aicoo_lab_experiment_path(experiment), notice: "Experiment, landing page, and prediction were created."
      end

      def bulk_convert_with_landing_pages
        candidates = AicooLabExperimentCandidate.where(id: selected_candidate_ids)
        result = AicooLabCandidateConverter.new(candidates).call

        redirect_to admin_aicoo_lab_experiments_path,
                    notice: "Converted #{result.experiments.size} candidates with landing pages."
      end

      def generate
        result = AicooLabCandidateGenerator.new(count: 10).call
        redirect_to admin_aicoo_lab_candidates_path,
                    notice: "Generated #{result.created_candidates.size} experiment candidates."
      end

      private

      def set_candidate
        @candidate = AicooLabExperimentCandidate.find(params.expect(:id))
      end

      def filtered_candidates
        candidates = AicooLabExperimentCandidate.by_lab_priority
        candidates = candidates.where(status: params[:status]) if params[:status].present?
        candidates = candidates.where(experiment_type: params[:experiment_type]) if params[:experiment_type].present?
        candidates = candidates.where(market_category: params[:market_category]) if params[:market_category].present?
        candidates = candidates.where(acquisition_channel: params[:acquisition_channel]) if params[:acquisition_channel].present?
        candidates
      end

      def candidate_params
        params.expect(
          aicoo_lab_experiment_candidate: [
            :title, :description, :experiment_type, :market_category, :acquisition_channel,
            :expected_90d_profit_yen, :success_probability, :budget_yen, :estimated_work_minutes,
            :assumed_price_yen, :lp_word_count, :cta_count, :development_minutes, :feature_count,
            :rationale, :status, :neglect_loss_90d_yen, :neglect_loss_reason, :target_user, :problem_statement, :hypothesis, :validation_method,
            :expected_learning, :rejection_condition
          ]
        )
      end

      def selected_candidate_ids
        Array(params[:candidate_ids]).compact_blank
      end

      CandidateSummary = Data.define do
        def total_count
          AicooLabExperimentCandidate.count
        end

        def approval_pending_count
          AicooLabExperimentCandidate.where(status: "proposed").count
        end

        def converted_count
          AicooLabExperimentCandidate.where(status: "converted").count
        end
      end
    end
  end
end
