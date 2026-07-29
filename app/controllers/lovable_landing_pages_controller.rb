class LovableLandingPagesController < ApplicationController
  skip_before_action :load_daily_run_execution_status, :load_long_running_operation_monitor, only: :pipeline_status
  before_action :set_business
  before_action :set_generation_run, only: %i[
    update_prompt regenerate_prompt launch retry register_preview register_result
    fetch_result resume_result restore publish
  ]

  def show
    load_page_context
  end

  def pipeline_status
    load_pipeline_context
    render partial: "pipeline_overview", locals: pipeline_locals
  end

  def create
    candidate = @business.action_candidates.find_by(id: params[:action_candidate_id])
    pipeline = Aicoo::Lovable::LandingPagePipeline.new
    result = if candidate&.generation_source == "lp_learning"
      pipeline.enqueue_revision!(
        business: @business,
        action_candidate: candidate,
        change_request: candidate.metadata.to_h["lovable_change_request"].presence || candidate.metadata.to_h["improvement_reason"]
      )
    else
      pipeline.enqueue_create!(business: @business, action_candidate: candidate)
    end
    redirect_to result.generation_run.metadata.to_h.fetch("build_url"), allow_other_host: true
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable LP作成を開始できませんでした: #{e.message}"
  end

  def prepare
    candidate = @business.action_candidates.find_by(id: params[:action_candidate_id])
    pipeline = Aicoo::Lovable::LandingPagePipeline.new
    prototype = external_landing_page
    result = if prototype && params[:change_request].present?
      pipeline.prepare_external_revision!(
        business: @business,
        landing_page_prototype: prototype,
        action_candidate: candidate,
        change_request: params[:change_request]
      )
    elsif params[:change_request].present?
      pipeline.prepare_revision!(
        business: @business,
        action_candidate: candidate,
        change_request: params[:change_request]
      )
    elsif candidate&.generation_source == "lp_learning"
      pipeline.prepare_revision!(
        business: @business,
        action_candidate: candidate,
        change_request: candidate.metadata.to_h["lovable_change_request"].presence || candidate.metadata.to_h["improvement_reason"]
      )
    else
      pipeline.prepare_create!(business: @business, action_candidate: candidate)
    end
    redirect_to business_lovable_landing_page_path(@business, landing_page_id: prototype&.id, action_candidate_id: candidate&.id, anchor: "lovable-prompt"), notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable Promptを生成できませんでした: #{e.message}"
  end

  def revise
    candidate = @business.action_candidates.find_by(id: params[:action_candidate_id])
    pipeline = Aicoo::Lovable::LandingPagePipeline.new
    prototype = external_landing_page
    prepared = if prototype
      pipeline.prepare_external_revision!(
        business: @business,
        landing_page_prototype: prototype,
        change_request: params[:change_request],
        action_candidate: candidate
      )
    else
      pipeline.prepare_revision!(business: @business, change_request: params[:change_request], action_candidate: candidate)
    end
    result = pipeline.launch!(business: @business, generation_run: prepared.generation_run)
    redirect_to result.generation_run.metadata.to_h.fetch("build_url"), allow_other_host: true
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable修正を開始できませんでした: #{e.message}"
  end

  def update_prompt
    result = Aicoo::Lovable::LandingPagePipeline.new.update_prompt!(
      business: @business,
      generation_run: @generation_run,
      prompt: params[:prompt]
    )
    redirect_to studio_path(anchor: "lovable-prompt"), notice: result.message
  rescue StandardError => e
    redirect_to studio_path(anchor: "lovable-prompt"), alert: "Lovable Promptを保存できませんでした: #{e.message}"
  end

  def regenerate_prompt
    result = Aicoo::Lovable::LandingPagePipeline.new.regenerate_prompt!(business: @business, generation_run: @generation_run)
    redirect_to studio_path(anchor: "lovable-prompt"), notice: result.message
  rescue StandardError => e
    redirect_to studio_path(anchor: "lovable-prompt"), alert: "Lovable Promptを再生成できませんでした: #{e.message}"
  end

  def launch
    result = Aicoo::Lovable::LandingPagePipeline.new.launch!(business: @business, generation_run: @generation_run)
    redirect_to result.generation_run.metadata.to_h.fetch("build_url"), allow_other_host: true
  rescue StandardError => e
    redirect_to studio_path(anchor: "lovable-prompt"), alert: "Lovableを起動できませんでした: #{e.message}"
  end

  def retry
    result = Aicoo::Lovable::LandingPagePipeline.new.enqueue_retry!(business: @business, generation_run: @generation_run)
    redirect_to studio_path, notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable再送を開始できませんでした: #{e.message}"
  end

  def register_preview
    result = Aicoo::Lovable::LandingPagePipeline.new.register_preview!(
      business: @business,
      generation_run: @generation_run,
      preview_url: params[:preview_url],
      editor_url: params[:editor_url],
      project_id: params[:project_id]
    )
    redirect_to studio_path, notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Previewを登録できませんでした: #{e.message}"
  end

  def register_result
    result = Aicoo::Lovable::LandingPagePipeline.new.register_result!(
      business: @business,
      generation_run: @generation_run,
      project_url: params[:project_url],
      project_id: params[:project_id],
      result_repository: params[:result_repository],
      result_branch: params[:result_branch],
      preview_url: params[:preview_url]
    )
    redirect_to studio_path, notice: result.message
  rescue StandardError => e
    redirect_to studio_path, alert: "Lovable生成結果を登録できませんでした: #{e.message}"
  end

  def fetch_result
    raise ArgumentError, "生成結果Repositoryを先に登録してください。" if @generation_run.metadata.to_h["lovable_result_repository"].blank?

    enqueue_result_import(@generation_run)
    redirect_to studio_path, notice: "Lovable生成結果の取得・静的検証・公開処理を開始しました。"
  rescue StandardError => e
    redirect_to studio_path, alert: "Lovable生成結果を取得できませんでした: #{e.message}"
  end

  def resume_result
    raise ArgumentError, "生成結果Repositoryを先に登録してください。" if @generation_run.metadata.to_h["lovable_result_repository"].blank?

    @generation_run.update!(
      error_message: nil,
      metadata: @generation_run.metadata.to_h.merge(
        "pipeline_status" => "lovable_result_waiting",
        "lovable_status" => "result_registered",
        "lovable_error_code" => nil,
        "lovable_error_message" => nil,
        "manual_fix_resumed_at" => Time.current.iso8601
      )
    )
    enqueue_result_import(@generation_run)
    redirect_to studio_path, notice: "手動修正済みとしてLovable生成結果の取得を再開しました。"
  rescue StandardError => e
    redirect_to studio_path, alert: "処理を再開できませんでした: #{e.message}"
  end

  def restore
    result = Aicoo::Lovable::LandingPagePipeline.new.restore!(business: @business, generation_run: @generation_run)
    redirect_to studio_path, notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Versionを復元できませんでした: #{e.message}"
  end

  def publish
    prototype = external_landing_page
    if prototype
      unless @generation_run.metadata.to_h["publication_files"].present? &&
          @generation_run.metadata.to_h["static_validation_status"] == "succeeded"
        raise ArgumentError, "Lovable生成結果の取得と静的検証を先に完了してください。"
      end
      result = Aicoo::CloudflarePages::LandingPagePublisher.new.publish!(
        landing_page: prototype,
        generation_run: @generation_run
      )
      redirect_to studio_path, notice: "LPを#{result.github_path}へcommitし、Cloudflare Pagesの公開確認を開始しました。"
    else
      result = Aicoo::Lovable::PublicationCoordinator.new.call(business: @business, generation_run: @generation_run)
      redirect_to studio_path, notice: "#{result.message} #{result.issue_url}"
    end
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "公開処理を開始できませんでした: #{e.message}"
  end

  def compare
    load_page_context
    @before_version = @repository.find(params[:before_id]) || @versions.second
    @after_version = @repository.find(params[:after_id]) || @versions.first
  end

  private

  def set_business
    @business = Business.real_businesses.find(params.expect(:business_id))
  end

  def set_generation_run
    @generation_run = Aicoo::Lovable::VersionRepository.new(business: @business).find(params.expect(:generation_run_id))
    raise ActiveRecord::RecordNotFound unless @generation_run
  end

  def load_page_context
    @landing_page_prototype = external_landing_page
    internal_landing_page = @landing_page_prototype&.metadata.to_h&.dig("lovable_landing_page_id")&.then do |id|
      @business.aicoo_lab_landing_pages.find_by(id:)
    end
    @repository = Aicoo::Lovable::VersionRepository.new(
      business: @business,
      landing_page: internal_landing_page,
      landing_page_prototype: @landing_page_prototype
    )
    @versions = @repository.all.sort_by { |run| [ @repository.version(run), run.created_at ] }.reverse
    @current_version = @repository.current
    @prompt_version = @repository.latest if @repository.latest&.prompt.present?
    @prompt_editable = @prompt_version && @prompt_version.metadata.to_h["preview_url"].blank? && @prompt_version.metadata.to_h.dig("publication", "published") != true
    @published_version = @repository.published
    @landing_page = @current_version&.metadata.to_h&.dig("landing_page_id")&.then { |id| AicooLabLandingPage.find_by(id:) }
    @configuration = Aicoo::Lovable::Configuration.new
    load_pipeline_context(repository: @repository)
    source_candidate_id = params[:action_candidate_id].presence || @prompt_version&.metadata.to_h&.dig("action_candidate_id")
    @source_action_candidate = @business.action_candidates.active_for_ranking.find_by(id: source_candidate_id)
    @current_learning = @published_version && Aicoo::Lovable::LearningSummary.new(business: @business, generation_run: @published_version).call
    @learning_comparison = Aicoo::Lovable::LandingPageLearningComparison.new(business: @business, repository: @repository).call
    @version_learning = @versions.to_h do |run|
      [ run.id, run.metadata.to_h["learning"].presence || (run.metadata.to_h.dig("publication", "published") == true ? Aicoo::Lovable::LearningSummary.new(business: @business, generation_run: run).call : {}) ]
    end
  end

  def load_pipeline_context(repository: nil)
    @landing_page_prototype ||= external_landing_page
    @repository = repository if repository
    @pipeline_version = repository ? repository.latest : latest_pipeline_version
    @lovable_task = @pipeline_version&.metadata.to_h&.dig("auto_revision_task_id")&.then do |id|
      @business.auto_revision_tasks.find_by(id:)
    end
    @pipeline_analytics_site = AicooAnalyticsSite.where(business: @business).recent.first
    @pipeline_learning_snapshot = if @landing_page_prototype
      AicooDataSnapshot
        .where(source_type: "landing_page_analytics", source_id: @landing_page_prototype.id)
        .recent
        .first
    end
    @pipeline_overview = Aicoo::Lovable::PipelineOverview.new(
      generation_run: @pipeline_version,
      landing_page: @landing_page_prototype,
      task: @lovable_task,
      business: @business,
      analytics_site: @pipeline_analytics_site,
      learning_snapshot: @pipeline_learning_snapshot,
      webhook_diagnostics: Aicoo::Lovable::GithubWebhookConfiguration.new.diagnostics,
      cloudflare_configuration: Aicoo::CloudflarePages::Configuration.new,
      webhook_url: github_webhook_url
    )
  end

  def latest_pipeline_version
    scope = AicooLabGenerationRun
      .where(generation_type: "lp_generation")
      .where("metadata ->> 'pipeline' = ?", Aicoo::Lovable::VersionRepository::PIPELINE_KEY)
      .where("metadata ->> 'business_id' = ?", @business.id.to_s)
    if @landing_page_prototype
      scope = scope.where("metadata ->> 'landing_page_prototype_id' = ?", @landing_page_prototype.id.to_s)
    end
    scope.order(created_at: :desc).first
  end

  def pipeline_locals
    {
      business: @business,
      landing_page: @landing_page_prototype,
      generation_run: @pipeline_version,
      task: @lovable_task,
      overview: @pipeline_overview
    }
  end

  def external_landing_page
    prototype_id = params[:landing_page_id].presence || @generation_run&.metadata.to_h&.dig("landing_page_prototype_id")
    return if prototype_id.blank?

    @business.business_prototypes.active.external_landing_pages.find_by(id: prototype_id)
  end

  def studio_path(anchor: nil)
    prototype_id = @generation_run&.metadata.to_h&.dig("landing_page_prototype_id") || params[:landing_page_id]
    business_lovable_landing_page_path(@business, landing_page_id: prototype_id, anchor:)
  end

  def enqueue_result_import(generation_run)
    Aicoo::LovableResultImportJob.perform_later(generation_run.id)
  end
end
