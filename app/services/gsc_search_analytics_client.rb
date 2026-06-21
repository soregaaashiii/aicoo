require "net/http"
require "json"
require "erb"

class GscSearchAnalyticsClient
  API_BASE = "https://www.googleapis.com/webmasters/v3/sites/"

  class Error < StandardError; end

  def initialize(oauth_client: GoogleOauthClient.new)
    @oauth_client = oauth_client
  end

  def query(site_url:, start_date:, end_date:, dimensions: [ "query" ], row_limit: 1_000)
    uri = URI("#{API_BASE}#{ERB::Util.url_encode(site_url)}/searchAnalytics/query")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@oauth_client.access_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      startDate: start_date.to_s,
      endDate: end_date.to_s,
      dimensions:,
      type: "web",
      rowLimit: row_limit
    )

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    raise Error, "GSC API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "GSC response could not be parsed: #{e.message}"
  end
end
