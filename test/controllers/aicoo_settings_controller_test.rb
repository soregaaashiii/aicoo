require "test_helper"

class AicooSettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows current auto queue setting" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)

    get aicoo_setting_url

    assert_response :success
    assert_includes response.body, "AICOO設定"
    assert_includes response.body, "データ整備タスク自動キュー投入"
    assert_includes response.body, "Owner Execution Queue"
    assert_includes response.body, "Strategic Philosophy"
    assert_includes response.body, "Strategic Learning Guardrail"
    assert_includes response.body, "AICOO全体設定センター"
    assert_select "#global-connections"
    assert_select "#global-connection-github", text: /GitHub/
    assert_select "#global-connection-cloudflare", text: /Cloudflare/
    assert_select "#global-connection-ga4", text: /GA4/
    assert_select "#global-connection-gsc", text: /GSC/
    assert_select "#global-connection-webhook", text: /Webhook/
    assert_select "#global-connection-cloudflare a[href='#{admin_cloudflare_connection_path}']"
    assert_includes response.body, "Google"
    assert_includes response.body, "Search / SEO"
    assert_includes response.body, "Social"
    assert_includes response.body, "Behavior"
    assert_includes response.body, "Ads"
    assert_includes response.body, "AI / Development"
    assert_includes response.body, "Connected"
    assert_includes response.body, "Not configured"
    assert_includes response.body, "Test connection"
    assert_includes response.body, "Data Source Cost Engine"
    assert_includes response.body, "SERP"
    assert_includes response.body, "manual"
    assert_includes response.body, "developer_token"
    assert_includes response.body, "Bearer Token"
    assert_includes response.body, "自動投入ON"
  end

  test "renders saved connection states with one cost engine and no external request" do
    DataSourceCostProfile.ensure_defaults!
    AicooSetting.current
    cost_engine_builds = 0
    original_new = Aicoo::CostEngine.method(:new)
    statements = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"

      statements << payload[:sql]
    end

    with_singleton_method(Net::HTTP, :start, ->(*) { flunk("settings GET must not call an external API") }) do
      with_singleton_method(Aicoo::CostEngine, :new, lambda { |*args, **kwargs|
        cost_engine_builds += 1
        original_new.call(*args, **kwargs)
      }) do
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          get aicoo_setting_url
        end
      end
    end

    setting_selects = statements.count do |sql|
      sql.match?(/SELECT .* FROM "business_data_source_settings"/m)
    end
    writes = statements.grep(/\A\s*(?:INSERT|UPDATE|DELETE)/i)
    assert_response :success
    assert_equal 1, cost_engine_builds
    assert_equal 1, setting_selects
    assert_empty writes
    assert_not statements.any? { |sql| sql.include?("data_imports") }
    assert_not statements.any? { |sql| sql.include?("aicoo_lab_landing_page_publication_events") }
  end

  test "running operation refresh uses the lightweight status endpoint" do
    AicooDailyRun.create!(
      target_date: Date.current,
      status: "running",
      source: "manual",
      started_at: 1.minute.ago
    )

    get aicoo_setting_url

    assert_response :success
    assert_select "[data-aicoo-auto-refresh-url='#{aicoo_operation_status_path}']", count: 1

    get aicoo_operation_status_url

    assert_response :success
    assert_select "#aicoo-operation-status-panel", count: 1
    assert_not_includes response.body, "AICOO全体設定センター"
  end

  test "loads only displayed businesses and profile settings" do
    DataSourceCostProfile.ensure_defaults!
    visible_business = businesses(:suelog)
    hidden_business = Business.create!(name: "設定画面対象外", status: "paused", deleted_at: Time.current)
    visible_setting = BusinessDataSourceSetting.create!(business: visible_business, source_key: "ga4", enabled: false)
    hidden_setting = BusinessDataSourceSetting.create!(business: hidden_business, source_key: "ga4", enabled: false)
    unrelated_setting = BusinessDataSourceSetting.create!(business: visible_business, source_key: "unknown-source", enabled: false)

    get aicoo_setting_url

    assert_response :success
    assert_includes response.body, "business_data_sources[#{visible_business.id}][ga4][enabled]"
    assert_not_includes response.body, "business_data_sources[#{hidden_business.id}][ga4][enabled]"
    assert_not_includes response.body, "business_data_sources[#{visible_business.id}][unknown-source][enabled]"
    assert visible_setting.persisted?
    assert hidden_setting.persisted?
    assert unrelated_setting.persisted?
  end

  test "updates data source cost profiles and business usage" do
    DataSourceCostProfile.ensure_defaults!

    patch update_data_sources_aicoo_setting_url, params: {
      data_sources: {
        "serp" => {
          name: "SERP",
          enabled: "1",
          execution_mode: "manual",
          api_key: "",
          credentials: { endpoint: "https://serp.example.test" },
          monthly_budget_yen: "3000",
          monthly_spend_yen: "120",
          monthly_run_count: "4",
          average_cost_yen: "20",
          average_expected_profit_yen: "1000"
        }
      },
      business_data_sources: {
        businesses(:suelog).id.to_s => {
          "serp" => { enabled: "0" }
        }
      }
    }

    profile = DataSourceCostProfile.find_by!(source_key: "serp")
    setting = BusinessDataSourceSetting.find_by!(business: businesses(:suelog), source_key: "serp")

    assert_redirected_to aicoo_setting_url(anchor: "data-source-costs")
    assert_equal "manual", profile.execution_mode
    assert_equal 3000, profile.monthly_budget_yen
    assert_equal 20.to_d, profile.average_cost_yen
    assert_equal "https://serp.example.test", profile.credentials["endpoint"]
    assert_not setting.enabled?
  end

  test "updates auto queue setting on" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: false)

    patch aicoo_setting_url, params: {
      aicoo_setting: { auto_queue_data_preparation_tasks: "1" }
    }

    assert_redirected_to aicoo_setting_url
    assert AicooSetting.current.reload.auto_queue_data_preparation_tasks?
  end

  test "updates auto queue setting off" do
    AicooSetting.current.update!(auto_queue_data_preparation_tasks: true)

    patch aicoo_setting_url, params: {
      aicoo_setting: { auto_queue_data_preparation_tasks: "0" }
    }

    assert_redirected_to aicoo_setting_url
    assert_not AicooSetting.current.reload.auto_queue_data_preparation_tasks?
  end

  test "updates owner execution queue settings" do
    patch aicoo_setting_url, params: {
      aicoo_setting: {
        daily_owner_queue_limit: "7",
        auto_queue_low_risk_enabled: "1",
        auto_queue_medium_risk_enabled: "0",
        auto_queue_high_risk_enabled: "0"
      }
    }

    setting = AicooSetting.current.reload
    assert_redirected_to aicoo_setting_url
    assert_equal 7, setting.daily_owner_queue_limit
    assert setting.auto_queue_low_risk_enabled?
    assert_not setting.auto_queue_medium_risk_enabled?
    assert_not setting.auto_queue_high_risk_enabled?
  end

  test "updates strategic philosophy weights" do
    patch aicoo_setting_url, params: {
      aicoo_setting: {
        long_term_profit_weight: "60",
        short_term_profit_weight: "10",
        learning_weight: "20",
        automation_weight: "5",
        exploration_weight: "5"
      }
    }

    setting = AicooSetting.current.reload
    assert_redirected_to aicoo_setting_url
    assert_equal 60, setting.long_term_profit_weight
    assert_equal 10, setting.short_term_profit_weight
    assert_equal 20, setting.learning_weight
    assert_equal 5, setting.automation_weight
    assert_equal 5, setting.exploration_weight
  end

  test "updates strategic learning guardrail settings" do
    patch aicoo_setting_url, params: {
      aicoo_setting: {
        strategic_learning_enabled: "1",
        strategic_learning_max_boost_rate: "0.2",
        strategic_learning_max_penalty_rate: "0.1",
        strategic_learning_warning_threshold_rate: "0.05",
        strategic_learning_decision_log_min_count: "5"
      }
    }

    setting = AicooSetting.current.reload
    assert_redirected_to aicoo_setting_url
    assert setting.strategic_learning_enabled?
    assert_equal 0.2.to_d, setting.strategic_learning_max_boost_rate
    assert_equal 0.1.to_d, setting.strategic_learning_max_penalty_rate
    assert_equal 0.05.to_d, setting.strategic_learning_warning_threshold_rate
    assert_equal 5, setting.strategic_learning_decision_log_min_count
  end

  private

  def with_singleton_method(object, method_name, replacement)
    singleton_class = object.singleton_class
    original = object.method(method_name)
    singleton_class.define_method(method_name, replacement)
    yield
  ensure
    singleton_class.define_method(method_name, original)
  end
end
