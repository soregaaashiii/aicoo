require "test_helper"

module Aicoo
  class LandingPagePauseServiceTest < ActiveSupport::TestCase
    test "pauses and resumes landing page while preserving slug and seo fields" do
      landing_page = create_published_landing_page

      assert_difference("AicooLabLandingPagePublicationEvent.where(event_type: 'pause').count", 1) do
        LandingPagePauseService.pause(
          landing_page,
          pause_reason: "ai_quality",
          operator: "daily_run",
          comment: "品質スコア低下",
          metadata: { score: 42 }
        )
      end

      landing_page.reload
      assert_equal "paused", landing_page.public_status
      assert_equal "ai_quality", landing_page.pause_reason
      assert_equal "daily_run", landing_page.paused_by
      assert_equal "lp-pause-service", landing_page.published_slug
      assert_equal "SEO title", landing_page.seo_title

      assert_difference("AicooLabLandingPagePublicationEvent.where(event_type: 'resume').count", 1) do
        LandingPagePauseService.resume(landing_page, operator: "admin", comment: "確認完了")
      end

      landing_page.reload
      assert_equal "published", landing_page.public_status
      assert_nil landing_page.pause_reason
      assert_nil landing_page.pause_comment
      assert_nil landing_page.paused_at
      assert_equal "admin", landing_page.resumed_by
      assert_equal "lp-pause-service", landing_page.published_slug
      assert_equal "SEO title", landing_page.seo_title
    end

    private

    def create_published_landing_page
      experiment = AicooLabExperiment.create!(
        title: "Pause service",
        experiment_type: "lp",
        acquisition_channel: "sns",
        approval_status: "approved"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "Pause service headline",
        subheadline: "Sub",
        body: "Body",
        cta_text: "登録する",
        status: "published",
        public_status: "published",
        published_at: Time.current,
        published_slug: "lp-pause-service",
        seo_title: "SEO title",
        og_title: "OG title"
      )
    end
  end
end
