class ActionCandidatesController < ApplicationController
  before_action :set_action_candidate, only: %i[ show edit update destroy approve reject reevaluate_ai send_to_executor ]

  # GET /action_candidates or /action_candidates.json
  def index
    @businesses = Business.order(:name)
    @action_candidates = filtered_action_candidates
    @action_candidate_judge_scores = AicooJudge::ActionCandidateScore.new.score_map(@action_candidates)
  end

  # GET /action_candidates/1 or /action_candidates/1.json
  def show
    @action_prediction_precision = AicooJudge::ActionResultJudge.new.precision_for(@action_candidate)
    @action_candidate_judge_score = AicooJudge::ActionCandidateScore.new.score_for(@action_candidate)
    @score_snapshots = @action_candidate.action_candidate_score_snapshots.recent.limit(10)
    @action_execution_logs = @action_candidate.action_execution_logs.recent.limit(10)
  end

  # GET /action_candidates/new
  def new
    @action_candidate = ActionCandidate.new(status: "idea", action_type: "other", generation_source: "manual", success_probability: 0)
  end

  # GET /action_candidates/1/edit
  def edit
  end

  # POST /action_candidates or /action_candidates.json
  def create
    @action_candidate = ActionCandidate.new(action_candidate_params)

    respond_to do |format|
      if @action_candidate.save
        format.html { redirect_to @action_candidate, notice: "Action candidate was successfully created." }
        format.json { render :show, status: :created, location: @action_candidate }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @action_candidate.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /action_candidates/1 or /action_candidates/1.json
  def update
    respond_to do |format|
      if @action_candidate.update(action_candidate_params)
        format.html { redirect_to @action_candidate, notice: "Action candidate was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @action_candidate }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @action_candidate.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /action_candidates/1 or /action_candidates/1.json
  def destroy
    @action_candidate.destroy!

    respond_to do |format|
      format.html { redirect_to action_candidates_path, notice: "Action candidate was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def approve
    @action_candidate.approve!(approved_by: "owner")
    message = "ActionCandidate『#{@action_candidate.title}』を承認しました。承認待ちタスクから削除されました。"
    OwnerTaskCompletionLog.record_success!(
      task_type: "action_candidate_approval",
      target: @action_candidate,
      action_label: "承認",
      message:,
      metadata: { status: @action_candidate.status, approved_at: @action_candidate.approved_at }
    )
    redirect_back fallback_location: owner_dashboard_path, notice: message
  end

  def reject
    @action_candidate.update!(status: "rejected")
    message = "ActionCandidate『#{@action_candidate.title}』を却下しました。承認待ちタスクから削除されました。"
    OwnerTaskCompletionLog.record_success!(
      task_type: "action_candidate_approval",
      target: @action_candidate,
      action_label: "却下",
      message:,
      metadata: { status: @action_candidate.status }
    )
    redirect_back fallback_location: owner_tasks_path, notice: message
  end

  def reevaluate_ai
    AiActionReevaluationService.new(@action_candidate).call

    redirect_to @action_candidate, notice: "AI reevaluated this action candidate."
  rescue OpenaiResponsesClient::MissingApiKeyError => e
    redirect_to @action_candidate, alert: e.message
  rescue OpenaiResponsesClient::Error, ActiveRecord::RecordInvalid => e
    redirect_to @action_candidate, alert: "AI reevaluation failed: #{e.message}"
  end

  def send_to_executor
    unless executor_direct_sendable?
      redirect_to @action_candidate, alert: "Executorへ直接送れるのはデータ整備タスクまたはInsight候補だけです。"
      return
    end

    task = AicooExecutor::TaskBuilder.from_action_candidate(@action_candidate)
    redirect_to admin_aicoo_executor_task_path(task), notice: "ActionCandidateをExecutorへ送りました。"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_action_candidate
      @action_candidate = ActionCandidate.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def action_candidate_params
      params.expect(action_candidate: [ :business_id, :title, :description, :action_type, :department, :expected_hours, :cost_yen, :success_probability, :immediate_value_yen, :neglect_loss_90d_yen, :neglect_loss_reason, :strategic_value_score, :risk_reduction_score, :confidence_score, :data_confidence_score, :priority_score, :status, :generation_source, :execution_prompt, :evaluation_reason ])
    end

    def filtered_action_candidates
      candidates = ActionCandidate.includes(:business).order(created_at: :desc)
      candidates = candidates.where(business_id: params[:business_id]) if params[:business_id].present?
      candidates = candidates.where(action_type: params[:action_type]) if params[:action_type].present?
      candidates = candidates.where(department: params[:department]) if params[:department].present?
      if params[:status].present?
        candidates = candidates.where(status: params[:status])
      else
        candidates = candidates.active_for_ranking
      end
      if params[:data_confidence_score].present?
        candidates = candidates.where(data_confidence_score: params[:data_confidence_score].to_i..)
      end
      candidates
    end

    def executor_direct_sendable?
      @action_candidate.data_preparation? || @action_candidate.generation_source == "ai_insight"
    end
end
