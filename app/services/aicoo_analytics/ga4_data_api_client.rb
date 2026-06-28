require "json"
require "net/http"

module AicooAnalytics
  class Ga4DataApiClient
    API_BASE = "https://analyticsdata.googleapis.com/v1beta/properties/"

    class Error < StandardError; end

    def initialize(access_token:, timeout: 20)
      @access_token = access_token
      @timeout = timeout
    end

    def run_report(property_id:, start_date:, end_date:, dimensions: %w[date pagePath], metrics: default_metrics, limit: 1_000)
      uri = URI("#{API_BASE}#{normalized_property_id(property_id)}:runReport")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(request_body(start_date:, end_date:, dimensions:, metrics:, limit:))

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: @timeout,
        read_timeout: @timeout
      ) { |http| http.request(request) }
      raise Error, "GA4 API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "GA4 API timeout: #{e.message}"
    rescue JSON::ParserError => e
      raise Error, "GA4 response could not be parsed: #{e.message}"
    end

    private

    def request_body(start_date:, end_date:, dimensions:, metrics:, limit:)
      {
        dateRanges: [ { startDate: start_date.to_s, endDate: end_date.to_s } ],
        dimensions: dimensions.map { |name| { name: } },
        metrics: metrics.map { |name| { name: } },
        limit:
      }
    end

    def default_metrics
      %w[screenPageViews activeUsers sessions eventCount]
    end

    def normalized_property_id(property_id)
      property_id.to_s.sub(/\Aproperties\//, "")
    end
  end
end
