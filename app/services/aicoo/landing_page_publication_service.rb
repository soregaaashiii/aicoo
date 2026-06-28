module Aicoo
  class LandingPagePublicationService
    def self.publish!(landing_page, published_at: Time.current)
      new(landing_page).publish!(published_at:)
    end

    def self.schedule!(landing_page, scheduled_publish_at:)
      new(landing_page).schedule!(scheduled_publish_at:)
    end

    def self.archive!(landing_page)
      new(landing_page).archive!
    end

    def self.update_content!(landing_page, attributes:)
      new(landing_page).update_content!(attributes:)
    end

    def initialize(landing_page)
      @landing_page = landing_page
    end

    def publish!(published_at: Time.current)
      landing_page.update!(
        published_slug: landing_page.published_slug.presence || landing_page.ensure_published_slug,
        published_at:,
        scheduled_publish_at: nil,
        status: "published",
        public_status: "published"
      )
      landing_page.aicoo_lab_experiment.mark_status!("running")
      landing_page
    end

    def schedule!(scheduled_publish_at:)
      landing_page.schedule_publication!(scheduled_publish_at:)
      landing_page
    end

    def archive!
      landing_page.unpublish!
      landing_page
    end

    def update_content!(attributes:)
      allowed = attributes.slice(
        :headline, :subheadline, :body, :cta_text, :assumed_price_yen,
        :seo_title, :seo_description, :og_title, :og_description, :og_image_url,
        :canonical_url, :published_slug
      )
      landing_page.update!(allowed)
      landing_page
    end

    private

    attr_reader :landing_page
  end
end
