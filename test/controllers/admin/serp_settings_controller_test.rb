require "test_helper"

module Admin
  class SerpSettingsControllerTest < ActionDispatch::IntegrationTest
    test "shows serp settings and test search form" do
      get admin_serp_settings_url

      assert_response :success
      assert_includes response.body, "SERP設定"
      assert_includes response.body, "現在のProvider"
      assert_includes response.body, "SERP Optional Mode"
      assert_includes response.body, "SERP依存step"
      assert_includes response.body, "SERPなしで実行可能なstep"
      assert_includes response.body, "serp_fetch"
      assert_includes response.body, "action_candidate_generation"
      assert_includes response.body, "テスト検索"
      assert_includes response.body, "SERP Adapterでテスト検索"
    end

    test "shows saved serp analyses and latest error" do
      business = businesses(:suelog)
      success = business.serp_analyses.create!(
        keyword: "梅田 喫煙 カフェ",
        analyzed_at: Time.zone.local(2026, 6, 21, 8, 0),
        search_engine: "google",
        device: "desktop",
        provider: "serper",
        status: "success",
        result_count: 1,
        competition_score: 72
      )
      success.serp_results.create!(position: 1, title: "喫煙カフェ", url: "https://example.com", snippet: "梅田")
      business.serp_analyses.create!(
        keyword: "難波 喫煙 カフェ",
        analyzed_at: Time.zone.local(2026, 6, 21, 9, 0),
        search_engine: "google",
        device: "desktop",
        provider: "serper",
        status: "failed",
        error_message: "Rate limit"
      )

      get admin_serp_settings_url

      assert_response :success
      assert_includes response.body, "取得結果"
      assert_includes response.body, "保存済み分析"
      assert_includes response.body, "保存済み結果"
      assert_includes response.body, "梅田 喫煙 カフェ"
      assert_includes response.body, "難波 喫煙 カフェ"
      assert_includes response.body, "Rate limit"
    end

    test "test search uses adapter and displays normalized result" do
      result = Aicoo::Serp::SearchResult.new(
        provider: "serper",
        type: "google_search",
        query: "大阪 喫煙 カフェ",
        location: "Japan",
        language: "ja",
        fetched_at: Time.current.iso8601,
        organic_results: [
          {
            position: 1,
            title: "大阪の喫煙カフェ",
            url: "https://example.com/osaka-smoking-cafe",
            displayed_url: "example.com",
            snippet: "大阪で喫煙できるカフェの一覧",
            source: "serper",
            raw: {}
          }
        ],
        people_also_ask: [],
        related_searches: [],
        ai_overview: nil,
        raw_response: {}
      )

      stub_adapter(lambda { |**_kwargs| result }) do
        post test_search_admin_serp_settings_url, params: {
          serp_test: {
            provider: "serper",
            type: "google_search",
            query: "大阪 喫煙 カフェ",
            location: "Japan",
            language: "ja",
            limit: 10
          }
        }
      end

      assert_response :success
      assert_includes response.body, "SERPテスト検索が完了しました"
      assert_includes response.body, "大阪の喫煙カフェ"
      assert_includes response.body, "Provider非依存の共通形式"
    end

    test "test search displays adapter error" do
      stub_adapter(lambda { |**_kwargs| raise Aicoo::Serp::MissingApiKeyError, "SERPER_API_KEY が未設定です" }) do
        post test_search_admin_serp_settings_url, params: {
          serp_test: {
            provider: "serper",
            type: "google_search",
            query: "大阪 喫煙 カフェ"
          }
        }
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "SERPER_API_KEY が未設定です"
    end

    private

    def stub_adapter(handler)
      singleton = class << Aicoo::Serp::Adapter; self; end
      original_call = Aicoo::Serp::Adapter.method(:call)
      singleton.define_method(:call) { |**kwargs| handler.call(**kwargs) }
      yield
    ensure
      singleton.define_method(:call) { |**kwargs| original_call.call(**kwargs) }
    end
  end
end
