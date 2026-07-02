require "test_helper"

module Aicoo
  class CostEngineTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      DataSourceCostProfile.delete_all
      BusinessDataSourceSetting.delete_all
    end

    test "creates default profiles with serp as manual" do
      summary = CostEngine.new.call
      serp = summary.estimates.find { |estimate| estimate.source_key == "serp" }

      assert_equal "manual", serp.execution_mode
      assert serp.manual?
      assert_equal 18.to_d, serp.estimated_cost_yen
      assert_operator serp.roi, :>, 1
      assert_operator summary.manual_count, :>, 0
      assert_operator summary.auto_count, :>, 0
      assert_operator summary.smart_count, :>, 0
    end

    test "calculates business level disabled warning" do
      DataSourceCostProfile.ensure_defaults!
      BusinessDataSourceSetting.create!(business: @business, source_key: "serp", enabled: false)

      estimate = CostEngine.new(business: @business).estimate("serp")

      assert_not estimate.business_enabled
      assert_match(/このBusinessでOFF/, estimate.warning)
    end

    test "returns business connection status" do
      DataSourceCostProfile.ensure_defaults!
      credential = AicooGoogleCredential.create!(
        name: "吸えログGoogle認証",
        client_id: "client",
        client_secret: "secret",
        refresh_token: "refresh",
        connected_at: Time.current
      )
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        connection_status: "linked",
        property_identifier: "properties/123",
        credential_reference: "吸えログGoogle認証",
        metadata: {
          "google_credential_id" => credential.id,
          "connection_fields" => { "property_id" => "properties/123" }
        }
      )

      estimate = CostEngine.new(business: @business).estimate("ga4")

      assert estimate.linked?
      assert_equal "設定済み（Business個別設定）", estimate.connection_label
      assert_equal "healthy", estimate.connection_status_level
      assert_equal "properties/123", estimate.connection_summary
    end

    test "openai uses global env api key without business binding" do
      original = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "env-openai-key"
      DataSourceCostProfile.ensure_defaults!
      DataSourceCostProfile.find_by!(source_key: "openai").update!(api_key: nil)

      estimate = CostEngine.new(business: @business).estimate("openai")

      assert estimate.linked?
      assert_equal "設定済み（全体設定を使用）", estimate.connection_label
      assert_equal "healthy", estimate.connection_status_level
      assert_equal "OPENAI_API_KEY", estimate.connection_summary
    ensure
      ENV["OPENAI_API_KEY"] = original
    end

    test "openai reports missing when env and stored api key are absent" do
      original = ENV["OPENAI_API_KEY"]
      ENV.delete("OPENAI_API_KEY")
      DataSourceCostProfile.ensure_defaults!
      DataSourceCostProfile.find_by!(source_key: "openai").update!(api_key: nil)

      estimate = CostEngine.new(business: @business).estimate("openai")

      assert_not estimate.linked?
      assert_equal "未設定（未設定）", estimate.connection_label
      assert_equal "critical", estimate.connection_status_level
      assert_equal "OPENAI_API_KEY未設定", estimate.connection_summary
    ensure
      ENV["OPENAI_API_KEY"] = original
    end

    test "checks smart run only when signals and roi are enough" do
      DataSourceCostProfile.ensure_defaults!
      engine = CostEngine.new(business: @business)

      assert engine.should_smart_run?("explore", signals: { ctr_drop: true })
      assert_not engine.should_smart_run?("explore", signals: {})
      assert_not engine.should_smart_run?("serp", signals: { ctr_drop: true })
    end
  end
end
