module Aicoo
  class BusinessOwnedUrlPolicy
    require "uri"

    Result = Data.define(:url, :target_url_type, :reference_url, :fallback_url) do
      def owner_page?
        target_url_type.in?(%w[own_existing owner_page])
      end

      def external_reference?
        target_url_type == "external_reference"
      end

      def proposed_new?
        target_url_type == "proposed_new"
      end

      def invalid?
        target_url_type == "invalid"
      end

      def url_classification
        return "own_existing" if owner_page?

        target_url_type
      end
    end

    class << self
      def call(business:, url:, fallback: nil)
        new(business:, url:, fallback:).call
      end
    end

    def initialize(business:, url:, fallback: nil)
      @business = business
      @url = url.to_s.strip
      @fallback = fallback.to_s.strip.presence
    end

    def call
      fallback_url = owned_fallback_url
      return Result.new(nil, "invalid", nil, fallback_url) if url.blank?
      return classify_owner_path(normalized_relative_path, fallback_url) if owner_relative_path?

      uri = parsed_uri(url)
      return Result.new(nil, "invalid", nil, fallback_url) unless uri&.host
      return classify_owner_path(uri.request_uri.presence || "/", fallback_url, original_url: url) if owner_host?(uri.host)

      Result.new(nil, "external_reference", url, fallback_url)
    end

    private

    attr_reader :business, :url, :fallback

    def owner_relative_path?
      url.start_with?("/") && !Aicoo::ActionTargetUrlResolver.metric_reference?(url)
    end

    def normalized_relative_path
      url.split(/[?#]/, 2).first.presence || "/"
    end

    def classify_owner_path(path, fallback_url, original_url: nil)
      normalized = path.to_s.split(/[?#]/, 2).first.presence || "/"
      return Result.new(nil, "invalid", nil, fallback_url) if invalid_path?(normalized)
      return Result.new(original_url.presence || normalized, "own_existing", nil, fallback_url) if known_existing_path?(normalized)
      return Result.new(normalized, "proposed_new", nil, fallback_url) if proposed_new_path?(normalized)

      Result.new(original_url.presence || normalized, "own_existing", nil, fallback_url)
    end

    def invalid_path?(path)
      return true if path.include?("/-")

      article_slug(path).then do |slug|
        slug.present? && (slug == "-" || slug.start_with?("-") || slug.match?(/\Aarticle-[a-z0-9]+\z/i))
      end
    end

    def known_existing_path?(path)
      return true if path == "/"
      return true if path.in?(%w[/umeda /namba /shops /areas])
      return published_article_slug?(article_slug(path)) if article_slug(path).present?
      return published_landing_page_slug?(landing_page_slug(path)) if landing_page_slug(path).present?

      true
    end

    def proposed_new_path?(path)
      article_slug(path).present? || landing_page_slug(path).present?
    end

    def article_slug(path)
      path.to_s[%r{\A/articles/([^/?#]+)\z}, 1]
    end

    def landing_page_slug(path)
      path.to_s[%r{\A/(?:lp|mvp)/([^/?#]+)\z}, 1]
    end

    def published_article_slug?(slug)
      return false if slug.blank?

      ::Suelog::Article.published.where(slug:).exists?
    rescue StandardError
      false
    end

    def published_landing_page_slug?(slug)
      return false if slug.blank?

      AicooLabLandingPage.publicly_available.where(published_slug: slug).exists?
    end

    def owner_host?(host)
      owner_hosts.include?(host.to_s.downcase)
    end

    def owner_hosts
      @owner_hosts ||= begin
        hosts = []
        hosts.concat(hosts_from_url(business&.business_execution_profile&.production_url))
        hosts.concat(hosts_from_url(business&.gsc_site_url))
        hosts.concat(hosts_from_url(business&.metadata.to_h["production_url"]))
        hosts.concat(hosts_from_url(business&.metadata.to_h["public_url"]))
        hosts.concat(%w[suelog.jp www.suelog.jp]) if suelog_business?
        hosts.compact_blank.map(&:downcase).uniq
      end
    end

    def owned_fallback_url
      @owned_fallback_url ||= begin
        return fallback if fallback.present? && fallback_owned?

        business&.business_execution_profile&.production_url.presence ||
          business&.gsc_site_url.presence ||
          business&.metadata.to_h["production_url"].presence ||
          (suelog_business? ? "https://suelog.jp/" : "/")
      end
    end

    def fallback_owned?
      return true if fallback.start_with?("/")

      uri = parsed_uri(fallback)
      uri&.host.present? && owner_host?(uri.host)
    end

    def hosts_from_url(value)
      uri = parsed_uri(value.to_s)
      return [] unless uri&.host

      [ uri.host ]
    end

    def parsed_uri(value)
      return nil if value.blank?

      URI.parse(value)
    rescue URI::InvalidURIError
      nil
    end

    def suelog_business?
      Aicoo::Suelog::SiteInsightsAdapter.target?(business)
    rescue NameError
      false
    end
  end
end
