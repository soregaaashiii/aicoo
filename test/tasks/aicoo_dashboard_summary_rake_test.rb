require "test_helper"
require "rake"

class AicooDashboardSummaryRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:dashboard_summary")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "dashboard_summary task exists and prints summary" do
    output, = capture_io do
      task.invoke
    end

    assert_includes output, "AICOO dashboard summary"
    assert_includes output, "Daily Run:"
    assert_includes output, "Judge:"
    assert_includes output, "Top Business:"
    assert_includes output, "Top Generation Source:"
  end

  private

  def task
    Rake::Task["aicoo:dashboard_summary"]
  end
end
