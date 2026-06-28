class PublicLandingPagesController < ApplicationController
  layout "public_lp"

  before_action :publish_due_landing_pages
  before_action :set_landing_page, only: %i[show cta_click scroll new_signup create_signup]
  before_action :set_rendering_context, only: %i[show new_signup create_signup]

  def index
    @landing_pages = published_landing_pages
    if params[:q].present?
      @landing_pages = @landing_pages.where(
        "LOWER(headline) LIKE :query OR LOWER(subheadline) LIKE :query OR LOWER(body) LIKE :query",
        query: "%#{params[:q].to_s.downcase}%"
      )
    end
    @landing_pages = @landing_pages.limit(100)
  end

  def show
    event_recorder.record!("view")
    @landing_page.aicoo_lab_experiment.increment!(:current_pv)
    render "aicoo_lab/previews/show"
  end

  def cta_click
    event_recorder.record!("cta_click")
    redirect_to public_lp_signup_path(@landing_page.published_slug)
  end

  def scroll
    event_recorder.record!("scroll", metadata: { depth: params[:depth].to_i.clamp(0, 100) })
    head :no_content
  end

  def new_signup
    @signup = @landing_page.aicoo_lab_signups.new
    render "aicoo_lab/previews/new_signup"
  end

  def create_signup
    @signup = @landing_page.aicoo_lab_signups.new(signup_params.merge(request_metadata))

    if @signup.save
      event_recorder.record!("signup", metadata: { signup_id: @signup.id })
      render "aicoo_lab/previews/signup_complete"
    else
      render "aicoo_lab/previews/new_signup", status: :unprocessable_content
    end
  end

  private

  def published_landing_pages
    AicooLabLandingPage
      .publicly_available
      .order(published_at: :desc, created_at: :desc)
  end

  def set_landing_page
    requested_slug = params.expect(:published_slug)
    @landing_page = published_landing_pages.find_by(published_slug: requested_slug)
    return if @landing_page

    slug_history = AicooLabLandingPageSlugHistory.find_by(slug: requested_slug)
    if slug_history&.aicoo_lab_landing_page&.publicly_visible?
      redirect_to public_lp_path(slug_history.aicoo_lab_landing_page.published_slug), status: :moved_permanently
      return
    end

    raise ActiveRecord::RecordNotFound
  end

  def set_rendering_context
    @lp_mode_label = "公開中"
    @lp_mode_description = nil
    @cta_click_path = public_lp_cta_click_path(@landing_page.published_slug)
    @scroll_event_path = public_lp_scroll_path(@landing_page.published_slug)
    @signup_path = public_lp_signup_path(@landing_page.published_slug)
    @back_path = public_lp_path(@landing_page.published_slug)
    @canonical_url = @landing_page.canonical_url.presence || helpers.public_absolute_url(public_lp_path(@landing_page.published_slug))
  end

  def publish_due_landing_pages
    AicooLabLandingPage.publish_due!
  end

  def event_recorder
    @event_recorder ||= AicooLabEventRecorder.new(@landing_page, request)
  end

  def signup_params
    params.expect(aicoo_lab_signup: [ :email, :note ])
  end

  def request_metadata
    {
      ip_hash: AicooLabEventRecorder.ip_hash_for(request.remote_ip),
      user_agent: request.user_agent,
      referrer: request.referrer
    }
  end
end
