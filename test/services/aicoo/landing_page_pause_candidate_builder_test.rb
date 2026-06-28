require "test_helper"

module Aicoo
  class LandingPagePauseCandidateBuilderTest < ActiveSupport::TestCase
    test "proposes low conversion published landing pages without pausing them" do
      landing_page = create_published_landing_page
      100.times { landing_page.aicoo_lab_landing_page_events.create!(event_type: "view") }

      candidates = LandingPagePauseCandidateBuilder.new.call

      candidate = candidates.find { |item| item.landing_page == landing_page }
      assert candidate
      assert_equal "conversion_low", candidate.reason
      assert_equal "published", landing_page.reload.public_status
    end

    private

    def create_published_landing_page
      experiment = AicooLabExperiment.create!(
        title: "Pause candidate",
        experiment_type: "lp",
        acquisition_channel: "sns",
        approval_status: "approved"
      )
      experiment.create_aicoo_lab_landing_page!(
        headline: "Pause candidate headline",
        subheadline: "Sub",
        body: "Body",
        cta_text: "登録する",
        status: "published",
        public_status: "published",
        published_at: Time.current,
        published_slug: "lp-pause-candidate"
      )
    end
  end
end
