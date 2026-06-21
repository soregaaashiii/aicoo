require "test_helper"

module AicooLab
  class PreviewsControllerTest < ActionDispatch::IntegrationTest
    test "preview access creates view event and increments current pv" do
      experiment = AicooLabExperiment.create!(title: "PV test", experiment_type: "lp", acquisition_channel: "sns")
      landing_page = create_landing_page(experiment)

      assert_difference("AicooLabLandingPageEvent.where(event_type: 'view').count") do
        assert_changes -> { experiment.reload.current_pv }, from: 0, to: 1 do
          get aicoo_lab_preview_url(landing_page.preview_slug)
        end
      end

      assert_response :success
    end

    test "cta click creates event and redirects to signup form" do
      experiment = AicooLabExperiment.create!(title: "CTA test", experiment_type: "lp", acquisition_channel: "sns")
      landing_page = create_landing_page(experiment)

      assert_difference("AicooLabLandingPageEvent.where(event_type: 'cta_click').count") do
        post aicoo_lab_preview_cta_click_url(landing_page.preview_slug)
      end

      assert_redirected_to aicoo_lab_preview_signup_url(landing_page.preview_slug)
    end

    test "signup creates signup and signup event" do
      experiment = AicooLabExperiment.create!(title: "Signup test", experiment_type: "lp", acquisition_channel: "sns")
      landing_page = create_landing_page(experiment)

      assert_difference("AicooLabSignup.count") do
        assert_difference("AicooLabLandingPageEvent.where(event_type: 'signup').count") do
          post aicoo_lab_preview_signup_url(landing_page.preview_slug), params: {
            aicoo_lab_signup: { email: "test@example.com", note: "Interested" }
          }
        end
      end

      assert_response :success
      assert_includes response.body, "登録ありがとうございます"
    end

    test "shows landing page preview without authentication" do
      experiment = AicooLabExperiment.create!(title: "Public preview test", experiment_type: "lp", acquisition_channel: "sns")
      landing_page = create_landing_page(experiment, headline: "Public preview headline")

      get aicoo_lab_preview_url(landing_page.preview_slug)

      assert_response :success
      assert_includes response.body, "Public preview headline"
      assert_includes response.body, "事前登録する"
    end

    private

    def create_landing_page(experiment, headline: "Preview headline")
      experiment.create_aicoo_lab_landing_page!(
        headline:,
        subheadline: "Public preview subheadline",
        body: "Public preview body",
        cta_text: "事前登録する",
        assumed_price_yen: 9_800
      )
    end
  end
end
