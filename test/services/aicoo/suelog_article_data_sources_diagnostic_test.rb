require "test_helper"

module Aicoo
  class SuelogArticleDataSourcesDiagnosticTest < ActiveSupport::TestCase
    setup do
      @business = Struct.new(:id, :name).new(1, "吸えログ")
      @diagnostic = SuelogArticleDataSourcesDiagnostic.new(business: @business)
    end

    test "normalizes article urls to joinable paths" do
      assert_equal "/articles/umeda-smoking-cafe", @diagnostic.send(:normalize_url, "https://www.suelog.jp/articles/UMEDA-Smoking-Cafe/?utm_source=x#section")
      assert_equal "/articles/umeda-smoking-cafe", @diagnostic.send(:normalize_url, "/articles/umeda-smoking-cafe/")
    end

    test "normalizes gsc rows with query and page dimensions" do
      rows = @diagnostic.send(:normalize_gsc_rows, [
        {
          "query" => "梅田 喫煙 カフェ",
          "page" => "https://suelog.jp/articles/umeda-smoking-cafe",
          "impressions" => "1,200",
          "clicks" => "30"
        }
      ])

      assert_equal 1, rows.size
      assert_equal "梅田 喫煙 カフェ", rows.first["query"]
      assert_equal "https://suelog.jp/articles/umeda-smoking-cafe", rows.first["page"]
      assert_equal 1200, rows.first["impressions"].to_i
      assert_equal 30, rows.first["clicks"].to_i
    end

    test "normalizes ga4 rows with page path and metrics" do
      rows = @diagnostic.send(:normalize_ga4_rows, [
        {
          "page_path" => "/articles/umeda-smoking-cafe",
          "pageviews" => "500",
          "active_users" => "120",
          "sessions" => "150",
          "event_name" => "scroll"
        }
      ])

      assert_equal 1, rows.size
      assert_equal "/articles/umeda-smoking-cafe", rows.first["page"]
      assert_equal 500, rows.first["pageviews"].to_i
      assert_equal 120, rows.first["active_users"].to_i
      assert_equal "scroll", rows.first["event_name"]
    end
  end
end
