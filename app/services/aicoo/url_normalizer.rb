require "cgi"
require "uri"

module Aicoo
  class UrlNormalizer
    DEFAULT_HOST = "suelog.jp"

    def self.call(value, default_host: DEFAULT_HOST)
      new(value, default_host:).call
    end

    def initialize(value, default_host: DEFAULT_HOST)
      @value = value
      @default_host = default_host
    end

    def call
      raw = value.to_s.strip
      return if raw.blank?

      raw = CGI.unescape(raw)
      uri = URI.parse(urlish?(raw) ? raw : "https://#{default_host}#{raw.start_with?('/') ? raw : "/#{raw}"}")
      path = uri.path.to_s.downcase
      path = "/" if path.blank?
      path = path.chomp("/") unless path == "/"
      path
    rescue URI::InvalidURIError
      nil
    end

    private

    attr_reader :value, :default_host

    def urlish?(raw)
      raw.match?(%r{\Ahttps?://}i)
    end
  end
end
