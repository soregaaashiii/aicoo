require "test_helper"

module AicooAnalytics
  class ScheduleReadinessCheckerTest < ActiveSupport::TestCase
    test "returns not ready without enabled settings" do
      AnalyticsSourceSetting.update_all(enabled: false)

      result = ScheduleReadinessChecker.new.call

      assert_not result.ready
      assert_includes result.checks.map(&:status), "error"
      assert_includes result.checks.map(&:message), "有効なAnalytics設定がありません"
    end

    test "returns error when required fields are missing" do
      AnalyticsSourceSetting.create!(source_type: "ga4", name: "Broken GA4", property_id: "123456789").update_columns(property_id: nil)

      result = ScheduleReadinessChecker.new.call

      assert_not result.ready
      assert result.checks.any? { |check| check.status == "error" && check.message == "GA4設定にproperty_idがありません" }
    end

    test "returns warning when latest success run is missing" do
      AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Warning GSC",
        site_url: "sc-domain:suelog.jp",
        refresh_token: "refresh-token"
      )

      result = ScheduleReadinessChecker.new.call

      assert result.checks.any? { |check| check.status == "warning" && check.message == "直近取得がまだありません" }
    end

    test "returns ready with enabled setting credentials successful run data import and snapshot" do
      setting = AnalyticsSourceSetting.create!(
        source_type: "gsc",
        name: "Ready GSC",
        site_url: "sc-domain:suelog.jp",
        refresh_token: "refresh-token"
      )
      data_import = create_data_import
      setting.analytics_fetch_runs.create!(
        source_type: "gsc",
        status: "success",
        started_at: 2.minutes.ago,
        finished_at: 1.minute.ago,
        data_import_id: data_import.id,
        snapshot_count: 1,
        updated_neglect_loss_count: 1
      )

      result = ScheduleReadinessChecker.new.call

      assert result.ready
      assert result.checks.all? { |check| check.status != "error" }
      assert result.checks.any? { |check| check.message == "直近取得でSnapshotが作られています" }
    end

    private

    def create_data_import
      business = Business.create!(name: "Readiness data import")
      data_source = business.data_sources.create!(name: "Readiness GSC", source_type: "gsc")
      data_source.data_imports.create!(
        filename: "readiness.csv",
        content_type: "text/csv",
        row_count: 1,
        raw_text: "query,clicks\nsample,1\n",
        imported_at: Time.current
      )
    end
  end
end
