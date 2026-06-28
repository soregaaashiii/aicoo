module AicooLab
  class PublishedLandingPagesController < ApplicationController
    layout "public_lp"
    before_action :publish_due_landing_pages
    before_action :set_landing_page
    before_action :set_rendering_context

    def show
      event_recorder.record!("view")
      @landing_page.aicoo_lab_experiment.increment!(:current_pv)
      render "aicoo_lab/previews/show"
    end

    def cta_click
      event_recorder.record!("cta_click")
      redirect_to aicoo_lab_published_lp_signup_path(@landing_page.published_slug)
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

    def set_landing_page
      @landing_page = AicooLabLandingPage.publicly_available.find_by!(published_slug: params.expect(:published_slug))
    end

    def set_rendering_context
      @lp_mode_label = "公開中"
      @lp_mode_description = "公開中。このURLをSNSや外部に貼って検証できます"
      @cta_click_path = aicoo_lab_published_lp_cta_click_path(@landing_page.published_slug)
      @signup_path = aicoo_lab_published_lp_signup_path(@landing_page.published_slug)
      @back_path = aicoo_lab_published_lp_path(@landing_page.published_slug)
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
end
