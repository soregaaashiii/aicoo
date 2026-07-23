class LovableLandingPagesController < ApplicationController
  before_action :set_business
  before_action :set_generation_run, only: %i[update_prompt regenerate_prompt launch retry register_preview restore publish]

  def show
    load_page_context
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

  def restore
    result = Aicoo::Lovable::LandingPagePipeline.new.restore!(business: @business, generation_run: @generation_run)
    redirect_to studio_path, notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Versionを復元できませんでした: #{e.message}"
  end

  def publish
    result = Aicoo::Lovable::PublicationCoordinator.new.call(business: @business, generation_run: @generation_run)
    redirect_to studio_path, notice: "#{result.message} #{result.issue_url}"
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
    source_candidate_id = params[:action_candidate_id].presence || @prompt_version&.metadata.to_h&.dig("action_candidate_id")
    @source_action_candidate = @business.action_candidates.active_for_ranking.find_by(id: source_candidate_id)
    @current_learning = @published_version && Aicoo::Lovable::LearningSummary.new(business: @business, generation_run: @published_version).call
    @learning_comparison = Aicoo::Lovable::LandingPageLearningComparison.new(business: @business, repository: @repository).call
    @version_learning = @versions.to_h do |run|
      [ run.id, run.metadata.to_h["learning"].presence || (run.metadata.to_h.dig("publication", "published") == true ? Aicoo::Lovable::LearningSummary.new(business: @business, generation_run: run).call : {}) ]
    end
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
end
