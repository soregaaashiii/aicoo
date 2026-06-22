require "test_helper"
require "rake"

class AicooMetaEvaluationsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:snapshot_meta_evaluations")
    Rake::Task["aicoo:snapshot_meta_evaluations"].reenable
  end

  test "snapshot_meta_evaluations task exists" do
    assert Rake::Task.task_defined?("aicoo:snapshot_meta_evaluations")
  end

  test "snapshot_meta_evaluations task creates snapshots" do
    ActionCandidate.create!(
      business: businesses(:suelog),
      title: "Rake meta snapshot candidate",
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 1_000,
      success_probability: 1,
      expected_hours: 1
    )

    assert_difference("MetaEvaluationSnapshot.count", (Business.count + 1) * 5) do
      output, = capture_io do
        Rake::Task["aicoo:snapshot_meta_evaluations"].invoke("2026-06-21")
      end

      assert_includes output, "AICOO MetaEvaluator snapshot"
      assert_includes output, "recorded_on=2026-06-21"
    end
  end
end
