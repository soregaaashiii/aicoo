require "test_helper"

module Aicoo
  class LandingPageIndexingPayloadBuilderTest < ActiveSupport::TestCase
    test "builds indexing api ready payload" do
      experiment = AicooLabExperiment.create!(title: "Indexing test", experiment_type: "lp", acquisition_channel: "sns")
      landing_page = experiment.create_aicoo_lab_landing_page!(
        headline: "Indexing headline",
        subheadline: "Indexing subheadline",
        body: "Indexing body",
        cta_text: "事前登録する",
        status: "published",
        public_status: "published",
        published_at: Time.current,
        published_slug: "indexing-lp"
      )

      payload = LandingPageIndexingPayloadBuilder.call(landing_page, url: "https://example.com/lp/indexing-lp")

      assert_equal landing_page.id, payload[:landing_page_id]
      assert_equal "indexing-lp", payload[:slug]
      assert_equal "https://example.com/lp/indexing-lp", payload[:url]
      assert_equal "URL_UPDATED", payload[:type]
      assert_equal "published", payload[:public_status]
      assert payload[:requested_at].present?
    end
  end
end
