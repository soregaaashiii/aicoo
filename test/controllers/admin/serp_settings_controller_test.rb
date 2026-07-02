require "test_helper"

module Admin
  class SerpSettingsControllerTest < ActionDispatch::IntegrationTest
    test "shows serp settings and test search form" do
      get admin_serp_settings_url

      assert_response :success
      assert_includes response.body, "SERP設定"
      assert_includes response.body, "SERP Summary"
      assert_includes response.body, "全体設定"
      assert_includes response.body, "Provider"
      assert_includes response.body, "SERP Optional Mode"
      assert_includes response.body, "SERP依存step"
      assert_includes response.body, "SERPなしで実行可能なstep"
      assert_includes response.body, "serp_fetch"
      assert_includes response.body, "action_candidate_generation"
      assert_includes response.body, "Business設定"
      assert_includes response.body, "Keyword管理"
      assert_includes response.body, "実行状況"
      assert_includes response.body, "履歴"
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
      assert_includes response.body, "履歴"
      assert_includes response.body, "保存済み分析"
      assert_includes response.body, "保存済み結果"
      assert_includes response.body, "梅田 喫煙 カフェ"
      assert_includes response.body, "難波 喫煙 カフェ"
      assert_includes response.body, "Rate limit"
    end

    test "adds manual keywords without replacing existing keywords" do
      business = businesses(:suelog)
      business.business_serp_keywords.create!(keyword: "既存 KW", source: "manual", status: "active")

      assert_difference -> { business.business_serp_keywords.count }, 2 do
        post business_keywords_admin_serp_settings_url(business), params: {
          serp_keywords: { keywords: "梅田 喫煙\n難波 喫煙,既存 KW" }
        }
      end

      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{business.id}")
      assert business.business_serp_keywords.exists?(keyword: "梅田 喫煙", status: "active", source: "manual")
      assert business.business_serp_keywords.exists?(keyword: "難波 喫煙", status: "active", source: "manual")
      assert_equal 1, business.business_serp_keywords.where(keyword: "既存 KW").count
    end

    test "approves and excludes suggested keywords" do
      keyword = businesses(:suelog).business_serp_keywords.create!(
        keyword: "梅田 喫煙 カフェ",
        source: "ai_suggested",
        status: "pending",
        reason: "Business情報から生成"
      )

      patch approve_keyword_admin_serp_settings_url(keyword)
      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{keyword.business_id}")
      assert_equal "active", keyword.reload.status

      patch exclude_keyword_admin_serp_settings_url(keyword), params: { serp_keyword: { reason: "対象外" } }
      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{keyword.business_id}")
      assert_equal "excluded", keyword.reload.status
      assert_equal "対象外", keyword.reason
    end

    test "bulk approves pending keywords for selected business" do
      business = businesses(:suelog)
      business.business_serp_keywords.create!(keyword: "梅田 喫煙", source: "ai_suggested", status: "pending")
      business.business_serp_keywords.create!(keyword: "難波 喫煙", source: "ai_suggested", status: "pending")

      post business_approve_pending_admin_serp_settings_url(business)

      assert_redirected_to admin_serp_settings_url(anchor: "serp-keywords")
      assert_equal 2, business.business_serp_keywords.where(status: "active").count
    end

    test "updates keyword text and marks manual priority" do
      keyword = businesses(:suelog).business_serp_keywords.create!(
        keyword: "梅田 喫煙",
        source: "manual",
        status: "active",
        priority_score: 50
      )

      patch keyword_admin_serp_settings_url(keyword), params: {
        serp_keyword: { keyword: "梅田 喫煙 カフェ", priority_score: 88 }
      }

      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{keyword.business_id}")
      keyword.reload
      assert_equal "梅田 喫煙 カフェ", keyword.keyword
      assert_equal 88, keyword.priority_score
      assert_equal true, keyword.metadata_json["manual_priority"]
    end

    test "destroys keyword from settings page" do
      keyword = businesses(:suelog).business_serp_keywords.create!(
        keyword: "削除 KW",
        source: "manual",
        status: "excluded"
      )

      assert_difference "BusinessSerpKeyword.count", -1 do
        delete destroy_keyword_admin_serp_settings_url(keyword)
      end
    end

    test "toggles business serp enabled from settings page" do
      business = businesses(:suelog)

      patch business_admin_serp_settings_url(business), params: { serp_business: { serp_enabled: "0" } }

      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{business.id}")
      assert_not business.reload.serp_enabled?
    end

    test "scans one business from settings page" do
      business = businesses(:suelog)
      result = Aicoo::Serp::ScanRunner::Result.new(
        started_at: Time.current,
        finished_at: Time.current,
        provider: "serper",
        target_business_count: 1,
        query_count: 1,
        success_count: 1,
        failed_count: 0,
        result_count: 10,
        duration_seconds: 1,
        estimated_cost_yen: 3,
        limit: 10,
        scan_batch_id: "test",
        analyses: []
      )

      stub_scan_runner(result) do
        post business_scan_admin_serp_settings_url(business)
      end

      assert_redirected_to admin_serp_settings_url(anchor: "serp-business-#{business.id}")
      assert_equal "吸えログのSERP取得が完了しました。1キーワード / 10件", flash[:notice]
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

    def stub_scan_runner(result)
      singleton = class << Aicoo::Serp::ScanRunner; self; end
      original_new = Aicoo::Serp::ScanRunner.method(:new)
      fake_runner = Object.new
      fake_runner.define_singleton_method(:call) { result }
      singleton.define_method(:new) { |**_kwargs| fake_runner }
      yield
    ensure
      singleton.define_method(:new) { |*args, **kwargs| original_new.call(*args, **kwargs) }
    end
  end
end
