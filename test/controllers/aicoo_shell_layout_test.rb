require "test_helper"
require "base64"

class AicooShellLayoutTest < ActionDispatch::IntegrationTest
  test "ceo mode uses unified header sidebar and breadcrumb" do
    get owner_focus_url

    assert_response :success
    assert_includes response.body, "AICOO"
    assert_includes response.body, "CEOモード"
    assert_includes response.body, "システムモード"
    assert_not_includes response.body, "Search"
    assert_not_includes response.body, "Notifications"
    assert_not_includes response.body, "Profile"
    assert_includes response.body, "目的から探す"
    assert_includes response.body, "今日どの事業を進めるか"
    assert_includes response.body, "ホーム"
    assert_includes response.body, "今日やること"
    assert_includes response.body, "新規事業探索"
    assert_includes response.body, "事業一覧"
    assert_includes response.body, "運用状況"
    assert_not_includes response.body, "Action Candidates"
    assert_not_includes response.body, "Auto Revision"
    assert_not_includes response.body, "New Business"
    assert_not_includes response.body, "Auto Build"
    assert_not_includes response.body, "Revenue"
    assert_not_includes response.body, "Learning"
    assert_not_includes response.body, "Dashboard"
    assert_not_includes response.body, "Pipeline E2E"
    assert_not_includes response.body, "Execution Profiles"
    assert_includes response.body, "現在位置"
    assert_select "a[href='#{admin_serp_settings_path}']", text: /新規事業探索/
    assert_select "a[href='#{owner_auto_revision_loop_path}']", text: /運用状況/
  end

  test "system mode uses purpose sidebar and breadcrumb" do
    get aicoo_daily_runs_url

    assert_response :success
    assert_includes response.body, "AICOO"
    assert_includes response.body, "システムモード"
    assert_includes response.body, "AICOOの運用・復旧"
    assert_includes response.body, "日次実行"
    assert_includes response.body, "Cron監視"
    assert_includes response.body, "Google連携"
    assert_select ".aicoo-sidebar a[href='#{admin_serp_settings_path}']", false
    assert_not_select ".aicoo-sidebar", text: /新規事業探索/
    assert_includes response.body, "自動ループ診断"
    assert_includes response.body, "活動学習"
    assert_includes response.body, "データ基盤"
    assert_includes response.body, "期待値補正"
    assert_includes response.body, "判断精度"
    assert_includes response.body, "AI予算"
    assert_includes response.body, "外部DB連携"
    assert_includes response.body, "全体設定"
    assert_includes response.body, "実行先設定"
    assert_includes response.body, "Codexルール"
    assert_not_includes response.body, "今日どの事業を進めるか"
    assert_includes response.body, "現在位置"
  end

  test "business pages use the ceo shell" do
    get business_url(businesses(:suelog))

    assert_response :success
    assert_includes response.body, "CEOモード"
    assert_includes response.body, "事業一覧"
    assert_includes response.body, "Google連携"
    assert_includes response.body, "現在位置"
  end

  test "business scoped detail pages keep business context" do
    action_candidate = action_candidates(:nagazakicho_article)

    get action_candidate_url(action_candidate)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "CEOモード"
    assert_select ".aicoo-sidebar-child.active strong", text: "事業一覧"
    assert_select ".purpose-context-bar", text: /改善案/
    assert_includes response.body, "この事業へ戻る"
  end

  test "action workspace keeps today context instead of business context" do
    action_candidate = action_candidates(:nagazakicho_article)

    get action_workspace_url(action_candidate)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "CEOモード"
    assert_select ".aicoo-sidebar-child.active strong", text: "今日やること"
    assert_not_select ".aicoo-sidebar-child.active strong", text: "事業一覧"
    assert_select ".aicoo-breadcrumb", text: /今日やること.*作業/m
    assert_not_includes response.body, "この事業へ戻る"
  end

  test "auto revision task pages stay inside the reduced ceo shell" do
    action_candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "自動改修サイドバー確認",
      status: "approved",
      action_type: "ui_improvement",
      immediate_value_yen: 5_000,
      success_probability: 0.4,
      expected_hours: 1,
      execution_prompt: "サイドバーが移動しないことを確認してください。"
    )
    task = AutoRevisionTask.from_action_candidate(action_candidate)

    get auto_revision_task_url(task)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "CEOモード"
    assert_select ".aicoo-sidebar-child strong", text: "運用状況"
    assert_not_select ".aicoo-sidebar-child strong", text: "Auto Revision"
    assert_not_select ".aicoo-sidebar-child strong", text: "Auto Build"
  end

  test "business revenue detail pages keep business context" do
    revenue_event = RevenueEvent.create!(
      business: businesses(:suelog),
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 500
    )

    get revenue_event_url(revenue_event)

    assert_response :success
    assert_select ".aicoo-sidebar-group.active .aicoo-sidebar-category strong", text: "CEOモード"
    assert_select ".aicoo-sidebar-child.active strong", text: "事業一覧"
    assert_select ".purpose-context-bar", text: /売上/
    assert_includes response.body, "この事業へ戻る"
  end

  test "ga4 tag is not rendered in test environment" do
    previous = ENV.fetch("GA4_MEASUREMENT_ID", nil)
    ENV["GA4_MEASUREMENT_ID"] = "G-E5KCHJTFVP"

    get owner_focus_url

    assert_response :success
    assert_not_includes response.body, "googletagmanager.com/gtag/js"
    assert_not_includes response.body, "G-E5KCHJTFVP"
  ensure
    previous.nil? ? ENV.delete("GA4_MEASUREMENT_ID") : ENV["GA4_MEASUREMENT_ID"] = previous
  end

  test "ga4 tag is not rendered on management layout even in production" do
    with_env_values(
      "GA4_MEASUREMENT_ID" => "G-E5KCHJTFVP",
      "AICOO_BASIC_AUTH_USERNAME" => "aicoo-admin",
      "AICOO_BASIC_AUTH_PASSWORD" => "secret-password"
    ) do
      with_rails_env("production") do
        get owner_focus_url, headers: basic_auth_headers("aicoo-admin", "secret-password")
      end
    end

    assert_response :success
    assert_not_includes response.body, "googletagmanager.com/gtag/js"
    assert_not_includes response.body, "G-E5KCHJTFVP"
    assert_not_includes response.body, "gtag('event', 'page_view'"
  end

  test "google site verification is not rendered in test environment" do
    previous = ENV.fetch("GOOGLE_SITE_VERIFICATION", nil)
    ENV["GOOGLE_SITE_VERIFICATION"] = "google-token"

    get owner_focus_url

    assert_response :success
    assert_not_includes response.body, "google-site-verification"
    assert_not_includes response.body, "google-token"
  ensure
    previous.nil? ? ENV.delete("GOOGLE_SITE_VERIFICATION") : ENV["GOOGLE_SITE_VERIFICATION"] = previous
  end

  private

  def basic_auth_headers(username, password)
    credentials = Base64.strict_encode64("#{username}:#{password}")
    { "HTTP_AUTHORIZATION" => "Basic #{credentials}" }
  end

  def with_env_values(values)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_rails_env(name)
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new(name) }
    yield
  ensure
    Rails.define_singleton_method(:env) { original.call }
  end
end
