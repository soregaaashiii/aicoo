class ActionCandidatesController < ApplicationController
  before_action :set_action_candidate, only: %i[
    show
    edit
    update
    destroy
    approve
    reject
    mark_executed
    reevaluate_ai
    send_to_executor
    generate_codex_prompt_draft
  ]

  # GET /action_candidates or /action_candidates.json
  def index
    @businesses = Business.real_businesses.order(:name)
    @action_candidates = filtered_action_candidates
    @action_candidate_judge_scores = AicooJudge::ActionCandidateScore.new.score_map(@action_candidates)
  end

  # GET /action_candidates/1 or /action_candidates/1.json
  def show
    @action_workspace = action_workspace_request?
    @action_prediction_precision = AicooJudge::ActionResultJudge.new.precision_for(@action_candidate)
    @action_candidate_judge_score = AicooJudge::ActionCandidateScore.new.score_for(@action_candidate)
    @score_snapshots = @action_candidate.action_candidate_score_snapshots.recent.limit(10)
    @action_execution_logs = @action_candidate.action_execution_logs.recent.limit(10)
    @action_execution = @action_candidate.action_execution
    @codex_prompt_draft = @action_candidate.codex_prompt_drafts.recent.first
    @execution_brief = Aicoo::ActionCandidateExecutionBrief.new(@action_candidate)
    @evidence_presenter = Aicoo::ActionCandidateEvidencePresenter.new(@action_candidate)
    @opportunity = OpportunityDiscoveryItem.find_by(id: @action_candidate.metadata.to_h["opportunity_id"]) ||
      @action_candidate.opportunity_discovery_items.order(updated_at: :desc).first
    @opportunity_related_candidates = related_opportunity_candidates(@opportunity)
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
    previous_status = @action_candidate.status
    result = Aicoo::ApprovalService.approve(@action_candidate, operator: "owner", source: "action_candidate_detail")
    redirect_record = result.redirect_record
    record_owner_decision!("approve", previous_status:)
    message = result.message
    OwnerTaskCompletionLog.record_success!(
      task_type: "action_candidate_approval",
      target: @action_candidate,
      action_label: redirect_record.is_a?(Business) ? "Business作成" : "改修開始",
      message:,
      metadata: {
        status: @action_candidate.status,
        approved_at: @action_candidate.approved_at,
        redirect_record_type: redirect_record&.class&.name,
        redirect_record_id: redirect_record&.id
      }.merge(result.metadata.to_h)
    )
    redirect_to safe_return_to || redirect_record || @action_candidate, notice: message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to safe_return_to || @action_candidate, alert: "Business化に失敗しました: #{e.record.errors.full_messages.to_sentence}"
  end

  def reject
    previous_status = @action_candidate.status
    result = Aicoo::ApprovalService.reject(@action_candidate, operator: "owner", source: "action_candidate_detail")
    record_owner_decision!("reject", previous_status:)
    message = result.message
    OwnerTaskCompletionLog.record_success!(
      task_type: "action_candidate_approval",
      target: @action_candidate,
      action_label: "却下",
      message:,
      metadata: { status: @action_candidate.status }
    )
    if (return_to = safe_return_to)
      redirect_to return_to, notice: message
    else
      redirect_back fallback_location: owner_tasks_path, notice: message
    end
  end

  def mark_executed
    if @action_candidate.executed?
      redirect_to action_workspace_path(@action_candidate), notice: "この施策はすでに実行済みです。"
      return
    end

    @action_candidate.mark_executed!(executed_by: "owner")
    OwnerTaskCompletionLog.record_success!(
      task_type: "action_candidate_execution",
      target: @action_candidate,
      action_label: "実行済み",
      message: "ActionCandidate『#{@action_candidate.title}』を実行済みにしました。",
      metadata: {
        status: @action_candidate.status,
        action_candidate_id: @action_candidate.id,
        action_execution_id: @action_candidate.action_execution&.id,
        action_result_id: @action_candidate.action_result&.id,
        executed_at: @action_candidate.metadata.to_h["executed_at"]
      }
    )
    redirect_to owner_focus_path, notice: "実行済みにしました。今日処理するActionから除外されます。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to action_workspace_path(@action_candidate), alert: "実行済み保存に失敗しました: #{e.record.errors.full_messages.to_sentence}"
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

  def generate_codex_prompt_draft
    unless @action_candidate.code_revision_execution_mode?
      redirect_to @action_candidate,
                  alert: "この候補は#{@action_candidate.execution_mode}のためCodex改修にはしません。実行単位に沿ってOwner/外注/管理画面で進めてください。"
      return
    end

    draft = CodexPromptDraft.from_action_candidate(@action_candidate)
    redirect_to owner_codex_prompt_draft_path(draft), notice: "Codex Prompt Draftを生成しました。"
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_action_candidate
      @action_candidate = ActionCandidate.find(params.expect(:id))
    end

    def related_opportunity_candidates(opportunity)
      return ActionCandidate.none unless opportunity

      ids = Array(opportunity.metadata.to_h["related_action_candidate_ids"]).map(&:to_i)
      ids |= [ opportunity.action_candidate_id ].compact
      ids |= ActionCandidate.where("metadata ->> 'opportunity_id' = ?", opportunity.id.to_s).pluck(:id)
      ActionCandidate.where(id: ids.uniq).order(Arel.sql("status = 'done' ASC, updated_at DESC"))
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

    def record_owner_decision!(decision_type, previous_status:)
      OwnerDecisionLog.record!(
        subject: @action_candidate,
        decision_type:,
        decision_source: "action_candidate_detail",
        previous_status:,
        new_status: @action_candidate.status
      )
    end

    def action_workspace_request?
      request.path.match?(%r{\A/actions/\d+})
    end

    def safe_return_to
      return_to = params[:return_to].to_s
      return if return_to.blank?
      return unless return_to.start_with?("/")
      return if return_to.start_with?("//")

      return_to
    end
end
