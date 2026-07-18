require "test_helper"

module Aicoo
  class SuelogGa4FetchE2eDiagnosticTest < ActiveSupport::TestCase
    setup do
      @business = Struct.new(:id, :name).new(2, "吸えログ")
      @diagnostic = SuelogGa4FetchE2eDiagnostic.new(business: @business, run_api: false, today: Date.new(2026, 7, 18))
    end

    test "normalizes GA4 API rows with date pagePath and hostName" do
      rows = @diagnostic.send(:normalize_api_rows, [
        {
          "dimensionValues" => [
            { "value" => "20260717" },
            { "value" => "/articles/umeda-smoking-cafe" },
            { "value" => "suelog.jp" }
          ],
          "metricValues" => [
            { "value" => "120" },
            { "value" => "40" },
            { "value" => "50" },
            { "value" => "8" },
            { "value" => "300" }
          ]
        }
      ])

      assert_equal 1, rows.size
      assert_equal "20260717", rows.first[:date]
      assert_equal "/articles/umeda-smoking-cafe", rows.first[:page_path]
      assert_equal "suelog.jp", rows.first[:host_name]
      assert_equal 120, rows.first[:screen_page_views]
      assert_equal 40, rows.first[:active_users]
      assert_equal 50, rows.first[:sessions]
    end

    test "classifies GA4 page paths by article shop lp and other" do
      counts = @diagnostic.send(:path_category_counts, [
        "/articles/umeda-smoking-cafe",
        "https://suelog.jp/shops/1?utm_source=ga4",
        "/lp/v6mkw8dqdlgzitnd",
        "/"
      ])

      assert_equal 1, counts[:articles]
      assert_equal 1, counts[:shops]
      assert_equal 1, counts[:lp]
      assert_equal 1, counts[:other]
    end

    test "builds diagnostic request with article-capable dimensions" do
      request = @diagnostic.send(:diagnostic_request_body)

      assert_equal %w[date pagePath hostName], request[:dimensions].map { |row| row[:name] }
      assert_includes request[:metrics].map { |row| row[:name] }, "screenPageViews"
      assert_nil request[:dimensionFilter]
    end
  end
end
