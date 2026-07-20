class LovableLandingPagesController < ApplicationController
  before_action :set_business
  before_action :set_generation_run, only: %i[retry register_preview restore publish]

  def show
    load_page_context
  end

  def create
    candidate = @business.action_candidates.find_by(id: params[:action_candidate_id])
    result = Aicoo::Lovable::LandingPagePipeline.new.enqueue_create!(business: @business, action_candidate: candidate)
    redirect_to business_lovable_landing_page_path(@business), notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable LP作成を開始できませんでした: #{e.message}"
  end

  def revise
    result = Aicoo::Lovable::LandingPagePipeline.new.enqueue_revision!(
      business: @business,
      change_request: params[:change_request]
    )
    redirect_to business_lovable_landing_page_path(@business), notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Lovable修正を開始できませんでした: #{e.message}"
  end

  def retry
    result = Aicoo::Lovable::LandingPagePipeline.new.enqueue_retry!(business: @business, generation_run: @generation_run)
    redirect_to business_lovable_landing_page_path(@business), notice: result.message
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
    redirect_to business_lovable_landing_page_path(@business), notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Previewを登録できませんでした: #{e.message}"
  end

  def restore
    result = Aicoo::Lovable::LandingPagePipeline.new.restore!(business: @business, generation_run: @generation_run)
    redirect_to business_lovable_landing_page_path(@business), notice: result.message
  rescue StandardError => e
    redirect_to business_lovable_landing_page_path(@business), alert: "Versionを復元できませんでした: #{e.message}"
  end

  def publish
    result = Aicoo::Lovable::PublicationCoordinator.new.call(business: @business, generation_run: @generation_run)
    redirect_to business_lovable_landing_page_path(@business), notice: "#{result.message} #{result.issue_url}"
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
    @repository = Aicoo::Lovable::VersionRepository.new(business: @business)
    @versions = @repository.all.sort_by { |run| [ @repository.version(run), run.created_at ] }.reverse
    @current_version = @repository.current
    @published_version = @repository.published
    @landing_page = @current_version&.metadata.to_h&.dig("landing_page_id")&.then { |id| AicooLabLandingPage.find_by(id:) }
    @configuration = Aicoo::Lovable::Configuration.new
    @source_action_candidate = @business.action_candidates.active_for_ranking.find_by(id: params[:action_candidate_id])
    @current_learning = @published_version && Aicoo::Lovable::LearningSummary.new(business: @business, generation_run: @published_version).call
  end
end
