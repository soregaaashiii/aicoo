require "test_helper"
require "rake"

class AicooProxyScoreWeightsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:adjust_proxy_score_weights")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "adjust_proxy_score_weights task exists" do
    assert Rake::Task.task_defined?("aicoo:adjust_proxy_score_weights")
  end

  test "runs with default date range" do
    output, = capture_io do
      task.invoke
    end

    assert_includes output, "AICOO proxy_score weight adjustment started"
    assert_includes output, "business_adjustment_log_count="
    assert_includes output, "global_adjustment_reason="
  end

  test "runs with specified date range" do
    output, = capture_io do
      task.invoke("2026-06-01", "2026-06-21")
    end

    assert_includes output, "start_date=2026-06-01"
    assert_includes output, "end_date=2026-06-21"
  end

  private

  def task
    Rake::Task["aicoo:adjust_proxy_score_weights"]
  end
end
