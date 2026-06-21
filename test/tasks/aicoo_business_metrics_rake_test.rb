require "test_helper"
require "rake"

class AicooBusinessMetricsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:import_business_metrics_daily")
    task.reenable
    backfill_task.reenable
  end

  teardown do
    task.reenable
    backfill_task.reenable
  end

  test "import_business_metrics_daily task exists" do
    assert Rake::Task.task_defined?("aicoo:import_business_metrics_daily")
  end

  test "imports yesterday when date is omitted" do
    output, = capture_io do
      task.invoke
    end

    assert_includes output, "date=#{Date.yesterday}"
    assert_includes output, "updated_business_count="
  end

  test "imports specified date" do
    date = Date.new(2026, 6, 21)

    output, = capture_io do
      task.invoke(date.to_s)
    end

    assert_includes output, "date=2026-06-21"
  end

  test "backfill_business_metrics_daily task exists" do
    assert Rake::Task.task_defined?("aicoo:backfill_business_metrics_daily")
  end

  test "backfills specified date range" do
    output, = capture_io do
      backfill_task.invoke("2026-06-01", "2026-06-02")
    end

    assert_includes output, "start_date=2026-06-01"
    assert_includes output, "end_date=2026-06-02"
    assert_includes output, "updated_metric_count="
  end

  test "backfill task fails clearly for invalid dates" do
    _output, error = capture_io do
      assert_raises(SystemExit) do
        backfill_task.invoke("bad-date", "2026-06-02")
      end
    end

    assert_includes error, "Invalid date range"
  end

  private

  def task
    Rake::Task["aicoo:import_business_metrics_daily"]
  end

  def backfill_task
    Rake::Task["aicoo:backfill_business_metrics_daily"]
  end
end
