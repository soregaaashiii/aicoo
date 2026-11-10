require "test_helper"

class Aicoo::LpIntegration::LandingPageStrategyBuilderTest < ActiveSupport::TestCase
  class MissingKeyClient
    def create_json(**)
      raise OpenaiResponsesClient::MissingApiKeyError, "OPENAI_API_KEY is not set."
    end
  end

  setup do
    @business = Business.create!(
      name: "LP Strategy Business",
      description: "問い合わせ対応を自動化するサービス",
      status: "building",
      business_type: "saas"
    )
    @campaign = @business.business_campaigns.create!(
      name: "Google Ads",
      campaign_type: "google_ads",
      status: "active",
      target_conversions: 4
    )
  end

  test "builds a complete strategy from existing data when OpenAI is unavailable" do
    strategy = Aicoo::LpIntegration::LandingPageStrategyBuilder.new(
      business: @business,
      campaign: @campaign,
      purpose: "google_ads",
      client: MissingKeyClient.new
    ).call

    assert_equal "existing_data_fallback", strategy.fetch("analysis_source")
    assert_equal "Google広告", strategy.fetch("purpose_label")
    assert_equal 4.0, strategy.fetch("expected_cv")
    assert_equal 0, strategy.fetch("expected_profit_yen")
    assert_equal "insufficient_profit_evidence", strategy.fetch("expected_value_source")
    assert strategy.fetch("keywords").present?
    assert strategy.fetch("target").present?
    assert strategy.fetch("cta").present?
    assert strategy.fetch("structure").present?
    assert strategy.fetch("seo_title").present?
    assert strategy.fetch("meta_description").present?
    assert strategy.fetch("reason").present?
  end

  test "passes only selected service pages to strategy analysis" do
    @business.business_services.create!(
      name: "Customer Console",
      url: "https://service.example.com",
      admin_url: "https://service.example.com/admin",
      other_url: "https://docs.example.com",
      user_page_analysis_enabled: false,
      admin_page_analysis_enabled: true,
      other_page_analysis_enabled: true
    )
    builder = Aicoo::LpIntegration::LandingPageStrategyBuilder.new(
      business: @business,
      campaign: @campaign,
      purpose: "google_ads",
      client: MissingKeyClient.new
    )

    pages = builder.send(:evidence).fetch("service").first.fetch("analysis_target_pages")

    assert_equal %w[admin other], pages.pluck("page_type")
    assert_equal [
      "https://service.example.com/admin",
      "https://docs.example.com"
    ], pages.pluck("url")
  end
end
