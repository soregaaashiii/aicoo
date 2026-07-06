module Aicoo
  class BusinessOwnedUrlPolicy
    require "uri"

    Result = Data.define(:url, :target_url_type, :reference_url, :fallback_url) do
      def owner_page?
        target_url_type == "owner_page"
      end

      def external_reference?
        target_url_type == "external_reference"
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
      return Result.new(fallback_url, fallback_url.present? ? "owner_page" : "unknown", nil, fallback_url) if url.blank?
      return Result.new(normalized_relative_path, "owner_page", nil, fallback_url) if owner_relative_path?

      uri = parsed_uri(url)
      return Result.new(fallback_url, fallback_url.present? ? "owner_page" : "unknown", nil, fallback_url) unless uri&.host
      return Result.new(url, "owner_page", nil, fallback_url) if owner_host?(uri.host)

      Result.new(fallback_url, fallback_url.present? ? "owner_page" : "external_reference", url, fallback_url)
    end

    private

    attr_reader :business, :url, :fallback

    def owner_relative_path?
      url.start_with?("/") && !Aicoo::ActionTargetUrlResolver.metric_reference?(url)
    end

    def normalized_relative_path
      url.split(/[?#]/, 2).first.presence || "/"
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
