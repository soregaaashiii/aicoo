require "test_helper"
require "rake"

class AicooAnalyticsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:analytics:daily_fetch")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "daily_fetch task exists" do
    assert Rake::Task.task_defined?("aicoo:analytics:daily_fetch")
  end

  test "daily_fetch exits normally when no enabled settings exist" do
    AnalyticsSourceSetting.update_all(enabled: false)
    called = false

    output, = capture_io do
      with_daily_fetch_job_stub(-> { called = true }) do
        task.invoke
      end
    end

    assert_not called
    assert_includes output, "有効なAnalyticsSourceSetting件数: 0"
    assert_includes output, "有効なAnalytics設定がありません"
  end

  test "daily_fetch calls DailyFetchJob perform_now" do
    AnalyticsSourceSetting.create!(
      source_type: "gsc",
      name: "Rake daily GSC",
      site_url: "sc-domain:suelog.jp"
    )
    called = false

    output, = capture_io do
      with_daily_fetch_job_stub(-> { called = true }) do
        task.invoke
      end
    end

    assert called
    assert_includes output, "有効なAnalyticsSourceSetting件数: 1"
    assert_includes output, "成功件数:"
    assert_includes output, "失敗件数:"
    assert_includes output, "作成DataImport件数:"
    assert_includes output, "Snapshot件数:"
    assert_includes output, "放置損失推定更新件数:"
  end

  private

  def task
    Rake::Task["aicoo:analytics:daily_fetch"]
  end

  def with_daily_fetch_job_stub(replacement)
    original = AicooAnalytics::DailyFetchJob.method(:perform_now)
    AicooAnalytics::DailyFetchJob.define_singleton_method(:perform_now) { replacement.call }
    yield
  ensure
    AicooAnalytics::DailyFetchJob.define_singleton_method(:perform_now) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
