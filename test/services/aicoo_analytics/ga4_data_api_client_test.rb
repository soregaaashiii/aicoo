require "test_helper"

module AicooAnalytics
  class Ga4DataApiClientTest < ActiveSupport::TestCase
    test "raises friendly message for invalid metric argument" do
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      response.define_singleton_method(:body) do
        {
          error: {
            status: "INVALID_ARGUMENT",
            message: "Field averageEngagementTime is not a valid metric. Did you mean engagementRate?"
          }
        }.to_json
      end

      error = assert_raises(Ga4DataApiClient::Error) do
        stub_http_start(lambda { |_host, _port, **_options, &_block| response }) do
          Ga4DataApiClient.new(access_token: "token").run_report(
            property_id: "123",
            start_date: Date.new(2026, 6, 1),
            end_date: Date.new(2026, 6, 28),
            metrics: %w[averageEngagementTime]
          )
        end
      end

      assert_includes error.message, "GA4 APIのmetric名が無効です"
      assert_includes error.message, "averageEngagementTime"
    end

    test "default metrics use GA4 Data API metric names" do
      request_body = nil
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { { rows: [] }.to_json }

      stub_http_start(lambda { |_host, _port, **_options, &block|
        http = Object.new
        http.define_singleton_method(:request) do |request|
          request_body = JSON.parse(request.body)
          response
        end
        block.call(http)
      }) do
        Ga4DataApiClient.new(access_token: "token").run_report(
          property_id: "123",
          start_date: Date.new(2026, 6, 1),
          end_date: Date.new(2026, 6, 28)
        )
      end

      metrics = request_body.fetch("metrics").map { |metric| metric.fetch("name") }
      assert_includes metrics, "totalUsers"
      assert_not_includes metrics, "activeUsers"
      assert_not_includes metrics, "averageEngagementTime"
    end

    private

    def stub_http_start(handler)
      singleton = class << Net::HTTP; self; end
      original_start = Net::HTTP.method(:start)
      singleton.define_method(:start) { |*args, **kwargs, &block| handler.call(*args, **kwargs, &block) }
      yield
    ensure
      singleton.define_method(:start) { |*args, **kwargs, &block| original_start.call(*args, **kwargs, &block) }
    end
  end
end
