module Aicoo
  class BusinessCapabilityProfile
    DEFAULT_CONVERSION_EVENTS = %w[conversion signup purchase inquiry phone_click map_click affiliate_click].freeze

    Profile = Data.define(
      :has_articles,
      :has_listings,
      :has_area_pages,
      :has_category_pages,
      :has_lp,
      :has_checkout,
      :has_signup,
      :conversion_events,
      :primary_assets,
      :content_assets,
      :manual_operation_assets
    ) do
      def to_h
        {
          "has_articles" => has_articles,
          "has_listings" => has_listings,
          "has_area_pages" => has_area_pages,
          "has_category_pages" => has_category_pages,
          "has_lp" => has_lp,
          "has_checkout" => has_checkout,
          "has_signup" => has_signup,
          "conversion_events" => conversion_events,
          "primary_assets" => primary_assets,
          "content_assets" => content_assets,
          "manual_operation_assets" => manual_operation_assets
        }
      end
    end

    def self.for(business)
      new(business).call
    end

    def initialize(business)
      @business = business
      @explicit = business.metadata.to_h.fetch("capabilities", {}).to_h
    end

    def call
      Profile.new(
        has_articles: capability_bool("has_articles", default_has_articles?),
        has_listings: capability_bool("has_listings", default_has_listings?),
        has_area_pages: capability_bool("has_area_pages", default_has_area_pages?),
        has_category_pages: capability_bool("has_category_pages", default_has_category_pages?),
        has_lp: capability_bool("has_lp", default_has_lp?),
        has_checkout: capability_bool("has_checkout", default_has_checkout?),
        has_signup: capability_bool("has_signup", default_has_signup?),
        conversion_events: explicit_array("conversion_events", default_conversion_events),
        primary_assets: explicit_array("primary_assets", default_primary_assets),
        content_assets: explicit_array("content_assets", default_content_assets),
        manual_operation_assets: explicit_array("manual_operation_assets", default_manual_operation_assets)
      )
    end

    private

    attr_reader :business, :explicit

    def capability_bool(key, fallback)
      return ActiveModel::Type::Boolean.new.cast(explicit[key]) if explicit.key?(key)

      fallback
    end

    def explicit_array(key, fallback)
      Array(explicit[key]).presence || fallback
    end

    def type
      business.business_type.to_s
    end

    def default_has_articles?
      type.in?(%w[seo_media content_media directory marketplace community]) ||
        business.business_activity_logs.where(resource_type: "Article").exists?
    end

    def default_has_listings?
      type.in?(%w[directory marketplace ecommerce community]) ||
        business.business_activity_logs.where(resource_type: %w[Shop Listing Product Item]).exists?
    end

    def default_has_area_pages?
      type.in?(%w[seo_media directory marketplace content_media])
    end

    def default_has_category_pages?
      type.in?(%w[seo_media directory marketplace content_media ecommerce])
    end

    def default_has_lp?
      type.in?(%w[landing_page mvp saas marketplace ecommerce other]) ||
        business.aicoo_lab_landing_pages.exists?
    end

    def default_has_checkout?
      type.in?(%w[saas ecommerce marketplace])
    end

    def default_has_signup?
      type.in?(%w[saas mvp marketplace community internal_tool])
    end

    def default_conversion_events
      events = []
      events << "signup" if default_has_signup?
      events << "purchase" if default_has_checkout?
      events += %w[phone_click map_click affiliate_click] if default_has_listings?
      events << "inquiry" if default_has_lp?
      events.presence || DEFAULT_CONVERSION_EVENTS
    end

    def default_primary_assets
      assets = []
      assets << "landing_page" if default_has_lp?
      assets << "article" if default_has_articles?
      assets << "listing" if default_has_listings?
      assets << "signup_flow" if default_has_signup?
      assets << "checkout" if default_has_checkout?
      assets.presence || [ "page" ]
    end

    def default_content_assets
      assets = []
      assets << "article" if default_has_articles?
      assets << "area_page" if default_has_area_pages?
      assets << "category_page" if default_has_category_pages?
      assets << "faq_section" if default_has_lp?
      assets.presence || [ "page_section" ]
    end

    def default_manual_operation_assets
      assets = []
      assets << "listing_data" if default_has_listings?
      assets << "customer_interview" if type.in?(%w[saas mvp landing_page])
      assets.presence || [ "owner_task" ]
    end
  end
end
