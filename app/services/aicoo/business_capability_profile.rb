module Aicoo
  class BusinessCapabilityProfile
    DEFAULT_CONVERSION_EVENTS = %w[conversion signup purchase inquiry phone_click map_click affiliate_click].freeze

    Asset = Data.define(
      :asset_type,
      :can_create,
      :can_update,
      :cost_yen,
      :estimated_minutes,
      :historical_success_rate,
      :expected_roi,
      :required_data
    ) do
      def to_h
        {
          "asset_type" => asset_type,
          "can_create" => can_create,
          "can_update" => can_update,
          "cost_yen" => cost_yen,
          "estimated_minutes" => estimated_minutes,
          "historical_success_rate" => historical_success_rate,
          "expected_roi" => expected_roi,
          "required_data" => required_data
        }
      end
    end

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
      :manual_operation_assets,
      :supply_assets,
      :quality_assets,
      :intent_keywords,
      :revenue_fit_rules,
      :work_cost_rules,
      :query_classification_rules,
      :assets
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
          "manual_operation_assets" => manual_operation_assets,
          "supply_assets" => supply_assets,
          "quality_assets" => quality_assets,
          "intent_keywords" => intent_keywords,
          "revenue_fit_rules" => revenue_fit_rules,
          "work_cost_rules" => work_cost_rules,
          "query_classification_rules" => query_classification_rules,
          "assets" => assets.map(&:to_h)
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
        manual_operation_assets: explicit_array("manual_operation_assets", default_manual_operation_assets),
        supply_assets: explicit_array("supply_assets", default_supply_assets),
        quality_assets: explicit_array("quality_assets", default_quality_assets),
        intent_keywords: explicit_hash("intent_keywords", default_intent_keywords),
        revenue_fit_rules: explicit_hash("revenue_fit_rules", default_revenue_fit_rules),
        work_cost_rules: explicit_hash("work_cost_rules", default_work_cost_rules),
        query_classification_rules: explicit_hash("query_classification_rules", default_query_classification_rules),
        assets: asset_knowledge
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

    def explicit_hash(key, fallback)
      explicit[key].to_h.presence || fallback
    end

    def asset_knowledge
      explicit_asset_knowledge.presence || default_asset_knowledge
    end

    def explicit_asset_knowledge
      Array(explicit["assets"]).filter_map do |raw_asset|
        attrs = raw_asset.to_h.deep_stringify_keys
        next if attrs["asset_type"].blank?

        asset_from(attrs)
      end
    end

    def asset_from(attrs)
      Asset.new(
        asset_type: attrs.fetch("asset_type").to_s,
        can_create: ActiveModel::Type::Boolean.new.cast(attrs.fetch("can_create", true)),
        can_update: ActiveModel::Type::Boolean.new.cast(attrs.fetch("can_update", true)),
        cost_yen: attrs.fetch("cost_yen", 0).to_i,
        estimated_minutes: attrs.fetch("estimated_minutes", attrs.fetch("estimated_time", 60)).to_i.clamp(5, 480),
        historical_success_rate: attrs.fetch("historical_success_rate", 0.4).to_d,
        expected_roi: attrs.fetch("expected_roi", 1.0).to_d,
        required_data: Array(attrs["required_data"]).compact_blank
      )
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

    def default_supply_assets
      assets = []
      assets << "listings" if default_has_listings?
      assets << "articles" if default_has_articles?
      assets << "area_pages" if default_has_area_pages?
      assets << "category_pages" if default_has_category_pages?
      assets << "landing_pages" if default_has_lp?
      assets << "signup_flow" if default_has_signup?
      assets << "checkout" if default_has_checkout?
      assets.presence || default_primary_assets
    end

    def default_quality_assets
      assets = []
      assets << "verified_listings" if default_has_listings?
      assets << "fresh_content" if default_has_articles?
      assets << "measured_conversion_events"
      assets << "internal_links" if default_has_articles? || default_has_lp?
      assets.uniq
    end

    def default_intent_keywords
      {
        "high" => (%w[予約 購入 料金 問い合わせ 申し込み 比較 違い 空席 営業中 見積もり] + default_conversion_events).uniq,
        "medium" => %w[おすすめ まとめ 導入 事例 使い方 選び方 ランキング],
        "low" => %w[とは 口コミ レビュー 評判 インスタ instagram]
      }
    end

    def default_revenue_fit_rules
      {
        "default" => 1.0,
        "high_intent" => 1.45,
        "medium_intent" => 1.15,
        "low_intent" => 0.75,
        "listings" => default_has_listings? ? 1.35 : 1.0,
        "articles" => default_has_articles? ? 1.15 : 1.0,
        "landing_pages" => default_has_lp? ? 1.25 : 1.0,
        "checkout" => default_has_checkout? ? 1.7 : 1.0,
        "signup" => default_has_signup? ? 1.5 : 1.0
      }
    end

    def default_work_cost_rules
      {
        "title_meta" => 20,
        "internal_links" => 35,
        "cta" => 45,
        "article" => 90,
        "lp" => 120,
        "supply_addition" => default_has_listings? ? 60 : 90,
        "quality_verification" => default_has_listings? ? 45 : 60,
        "measurement" => 45
      }
    end

    def default_query_classification_rules
      {
        "comparison" => %w[比較 違い vs versus 料金],
        "local" => %w[近く 周辺 エリア 駅 市 区 町],
        "how_to" => %w[方法 使い方 やり方 とは],
        "conversion" => default_intent_keywords["high"],
        "noise" => %w[インスタ instagram twitter x 画像 無料素材]
      }
    end

    def default_asset_knowledge
      assets = []
      assets << build_asset("articles", can_create: true, can_update: true, estimated_minutes: 90, success: 0.48, roi: 1.8, required_data: %w[gsc serp]) if default_has_articles?
      assets << build_asset("listings", can_create: true, can_update: true, estimated_minutes: 60, success: 0.55, roi: 1.6, required_data: %w[business_db activity]) if default_has_listings?
      assets << build_asset("area_pages", can_create: true, can_update: true, estimated_minutes: 80, success: 0.42, roi: 1.5, required_data: %w[gsc business_db]) if default_has_area_pages?
      assets << build_asset("category_pages", can_create: true, can_update: true, estimated_minutes: 80, success: 0.42, roi: 1.45, required_data: %w[gsc business_db]) if default_has_category_pages?
      assets << build_asset("landing_pages", can_create: true, can_update: true, estimated_minutes: 120, success: 0.38, roi: 1.7, required_data: %w[ga4 gsc]) if default_has_lp?
      assets << build_asset("comparison_pages", can_create: default_has_articles? || default_has_lp?, can_update: true, estimated_minutes: 100, success: 0.44, roi: 1.9, required_data: %w[gsc serp])
      assets << build_asset("faq", can_create: true, can_update: true, estimated_minutes: 35, success: 0.35, roi: 1.25, required_data: %w[gsc serp])
      assets << build_asset("cta", can_create: true, can_update: true, estimated_minutes: 45, success: 0.46, roi: 1.65, required_data: %w[ga4 conversion_events])
      assets << build_asset("internal_links", can_create: true, can_update: true, estimated_minutes: 40, success: 0.4, roi: 1.35, required_data: %w[gsc ga4])
      assets << build_asset("signup", can_create: false, can_update: true, estimated_minutes: 75, success: 0.4, roi: 1.7, required_data: %w[ga4 conversion_events]) if default_has_signup?
      assets << build_asset("checkout", can_create: false, can_update: true, estimated_minutes: 90, success: 0.36, roi: 1.8, required_data: %w[ga4 revenue]) if default_has_checkout?
      assets << build_asset("pricing", can_create: default_has_lp? || default_has_signup?, can_update: true, estimated_minutes: 70, success: 0.34, roi: 1.55, required_data: %w[ga4 revenue])
      assets.presence || [ build_asset("owner_tasks", can_create: true, can_update: true, estimated_minutes: 30, success: 0.35, roi: 1.0, required_data: %w[activity]) ]
    end

    def build_asset(asset_type, can_create:, can_update:, estimated_minutes:, success:, roi:, required_data:, cost_yen: 0)
      Asset.new(
        asset_type:,
        can_create:,
        can_update:,
        cost_yen:,
        estimated_minutes:,
        historical_success_rate: success.to_d,
        expected_roi: roi.to_d,
        required_data:
      )
    end
  end
end
