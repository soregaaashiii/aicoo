module AicooLab
  class PreviewsController < ApplicationController
    layout "aicoo_lab_preview"
    before_action :set_landing_page
    before_action :set_rendering_context

    def show
      event_recorder.record!("view")
      @landing_page.aicoo_lab_experiment.increment!(:current_pv)
    end

    def cta_click
      event_recorder.record!("cta_click")
      redirect_to aicoo_lab_preview_signup_path(@landing_page.preview_slug)
    end

    def new_signup
      @signup = @landing_page.aicoo_lab_signups.new
    end

    def create_signup
      @signup = @landing_page.aicoo_lab_signups.new(signup_params.merge(request_metadata))

      if @signup.save
        event_recorder.record!("signup", metadata: { signup_id: @signup.id })
        render :signup_complete
      else
        render :new_signup, status: :unprocessable_content
      end
    end

    private

    def set_landing_page
      @landing_page = AicooLabLandingPage.find_by!(preview_slug: params.expect(:preview_slug))
    end

    def set_rendering_context
      @lp_mode_label = "確認用"
      @lp_mode_description = "確認用。外部流入には使わない"
      @cta_click_path = aicoo_lab_preview_cta_click_path(@landing_page.preview_slug)
      @signup_path = aicoo_lab_preview_signup_path(@landing_page.preview_slug)
      @back_path = aicoo_lab_preview_path(@landing_page.preview_slug)
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
