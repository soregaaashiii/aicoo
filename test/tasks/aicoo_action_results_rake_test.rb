require "test_helper"
require "rake"

class AicooActionResultsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:evaluate_action_results")
    task.reenable
  end

  teardown do
    task.reenable
  end

  test "evaluate_action_results task exists" do
    assert Rake::Task.task_defined?("aicoo:evaluate_action_results")
  end

  test "diagnose_action_result_manual_actuals task exists" do
    assert Rake::Task.task_defined?("aicoo:diagnose_action_result_manual_actuals")
  end

  test "runs action result evaluation" do
    ActionResult.create!(
      action_candidate: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      executed_on: Date.yesterday,
      evaluated_on: Date.current
    )

    output, = capture_io do
      task.invoke
    end

    assert_includes output, "AICOO action result evaluation started"
    assert_includes output, "evaluated_or_skipped_count=1"
  end

  private

  def task
    Rake::Task["aicoo:evaluate_action_results"]
  end
end
