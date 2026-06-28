module Aicoo
  class LandingPageIndexingPayloadBuilder
    def self.call(landing_page, url:, type: "URL_UPDATED")
      new(landing_page, url:, type:).call
    end

    def initialize(landing_page, url:, type: "URL_UPDATED")
      @landing_page = landing_page
      @url = url
      @type = type
    end

    def call
      {
        landing_page_id: landing_page.id,
        slug: landing_page.published_slug,
        url:,
        type:,
        public_status: landing_page.public_status,
        requested_at: Time.current
      }
    end

    private

    attr_reader :landing_page, :url, :type
  end
end
