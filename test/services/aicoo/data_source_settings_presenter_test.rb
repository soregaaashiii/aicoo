require "test_helper"

module Aicoo
  class DataSourceSettingsPresenterTest < ActiveSupport::TestCase
    setup do
      DataSourceCostProfile.ensure_defaults!
      @business = businesses(:suelog)
    end

    test "serp is manual by default" do
      status = DataSourceSettingsPresenter.new.global_statuses.find { |item| item.source_key == "serp" }

      assert_equal "manual", status.execution_mode
      assert status.manual_paid
    end

    test "business uses global setting when global credentials are configured" do
      DataSourceCostProfile.find_by!(source_key: "serp").update!(api_key: "secret")

      status = DataSourceSettingsPresenter.new.business_status(@business, "serp")

      assert_equal "global", status.status_key
      assert_equal "🟢 全体設定使用", status.status_label
      assert status.uses_global
    end

    test "business status is individual when linked" do
      BusinessDataSourceSetting.create!(
        business: @business,
        source_key: "ga4",
        connection_status: "linked",
        property_identifier: "properties/123",
        metadata: {
          "source_binding" => { "use_global" => false },
          "connection_fields" => { "property_id" => "properties/123" }
        }
      )

      status = DataSourceSettingsPresenter.new.business_status(@business, "ga4")

      assert_equal "individual", status.status_key
      assert_equal "✅ 個別設定済み", status.status_label
      assert_not status.uses_global
    end

    test "business status is missing when global and individual are absent" do
      status = DataSourceSettingsPresenter.new.business_status(@business, "x")

      assert_equal "missing", status.status_key
      assert_equal "🔴 未設定", status.status_label
      assert_equal "critical", status.status_level
    end

    test "codex status is individual when business project fields are configured" do
      @business.update!(
        project_key: "suelog",
        local_project_path: "/apps/suelog",
        repository_name: "suelog"
      )

      status = DataSourceSettingsPresenter.new.codex_status(@business)

      assert_equal "individual", status.status_key
      assert_equal "✅ 個別設定済み", status.status_label
    end

    test "codex status is internal for aicoo created business" do
      @business.update!(created_by_aicoo: true, project_key: nil, local_project_path: nil, repository_name: nil)

      status = DataSourceSettingsPresenter.new.codex_status(@business)

      assert_equal "aicoo_internal", status.status_key
      assert_equal "🟢 AICOO内部プロジェクト（接続済み）", status.status_label
      assert_equal "healthy", status.status_level
      assert_equal "AICOO本体Repositoryを使用", status.summary
    end
  end
end
