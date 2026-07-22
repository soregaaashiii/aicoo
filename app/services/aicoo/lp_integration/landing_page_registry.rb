require "uri"

module Aicoo
  module LpIntegration
    class LandingPageRegistry
      PUBLIC_STATUSES = %w[draft published paused].freeze

      def initialize(business:)
        @business = business
      end

      def save!(attributes)
        values = attributes.to_h.deep_stringify_keys
        landing_page = find_or_initialize(values["landing_page_id"])
        source_type = values["source_type"].presence_in(Overview::SOURCE_TYPES.keys) || "manual"
        url = values["url"].presence
        repository_url = values["repository_url"].presence
        lovable_url = values["lovable_project_url"].presence
        metadata = landing_page.metadata.to_h.merge(
          "role" => BusinessPrototype::EXTERNAL_LANDING_PAGE_ROLE,
          "lp_name" => values["name"].presence || landing_page.name.presence || "LP",
          "lp_url" => url,
          "lp_repository_url" => repository_url,
          "lp_branch" => values["branch"].presence || "main",
          "lovable_project_url" => lovable_url,
          "lp_source_type" => source_type,
          "lp_public_status" => values["public_status"].presence_in(PUBLIC_STATUSES) || "draft",
          "ga4_page_path" => normalized_page_path(values["ga4_page_path"], url),
          "gsc_url" => url,
          "cta" => values["cta"].presence,
          "current_conversion_rate" => decimal_or_nil(values["current_conversion_rate"]),
          "improvement_target" => values["improvement_target"].presence,
          "hosting_provider" => "cloudflare_pages",
          "sync_status" => landing_page.metadata.to_h["sync_status"].presence || "not_synced",
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        ).compact
        landing_page.assign_attributes(
          name: metadata.fetch("lp_name"),
          prototype_type: SettingsUpdater::SOURCE_TYPE_MAP.fetch(source_type),
          location: source_location(source_type, repository_url:, lovable_url:, url:),
          status: "active",
          metadata:
        )
        landing_page.save!
        landing_page
      end

      def archive!(landing_page_id)
        landing_page = landing_pages.find(landing_page_id)
        landing_page.update!(
          status: "archived",
          metadata: landing_page.metadata.to_h.merge(
            "archived_at" => Time.current.iso8601,
            "archived_by" => "owner"
          )
        )
        landing_page
      end

      def find!(landing_page_id)
        landing_pages.find(landing_page_id)
      end

      private

      attr_reader :business

      def landing_pages
        business.business_prototypes.active.external_landing_pages
      end

      def find_or_initialize(landing_page_id)
        return business.business_prototypes.new if landing_page_id.blank?

        landing_pages.find(landing_page_id)
      end

      def source_location(source_type, repository_url:, lovable_url:, url:)
        return repository_url || lovable_url || url || "ZIP・書き出しコード（未指定）" if source_type == "zip_export"
        return repository_url || lovable_url || url || "手動指定（未設定）" if source_type == "manual"

        repository_url || lovable_url || url || raise(ArgumentError, "LPのGitHub、Lovable、URLのいずれかを入力してください。")
      end

      def normalized_page_path(explicit_path, url)
        path = explicit_path.to_s.strip
        path = URI.parse(url).path if path.blank? && url.present?
        path = "/" if path.blank?
        path = "/#{path}" unless path.start_with?("/")
        path.gsub(%r{/+}, "/")
      rescue URI::InvalidURIError
        explicit_path.presence || "/"
      end

      def decimal_or_nil(value)
        return if value.blank?

        BigDecimal(value.to_s).to_f
      rescue ArgumentError
        raise ArgumentError, "現在のCV率は数値で入力してください。"
      end
    end
  end
end
