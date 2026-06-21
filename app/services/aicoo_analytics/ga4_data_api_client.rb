require "json"
require "net/http"

module AicooAnalytics
  class Ga4DataApiClient
    API_BASE = "https://analyticsdata.googleapis.com/v1beta/properties/"

    class Error < StandardError; end

    def initialize(access_token:)
      @access_token = access_token
    end

    def run_report(property_id:, start_date:, end_date:)
      uri = URI("#{API_BASE}#{property_id}:runReport")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@access_token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(request_body(start_date:, end_date:))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      raise Error, "GA4 API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "GA4 response could not be parsed: #{e.message}"
    end

    private

    def request_body(start_date:, end_date:)
      {
        dateRanges: [ { startDate: start_date.to_s, endDate: end_date.to_s } ],
        dimensions: [ { name: "date" }, { name: "pagePath" } ],
        metrics: [
          { name: "screenPageViews" },
          { name: "activeUsers" },
          { name: "sessions" },
          { name: "eventCount" }
        ],
        limit: 1_000
      }
    end
  end
end
