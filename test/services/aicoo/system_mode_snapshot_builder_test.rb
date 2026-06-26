require "test_helper"

module Aicoo
  class SystemModeSnapshotBuilderTest < ActiveSupport::TestCase
    test "creates snapshot from system mode monitor" do
      snapshot = nil

      assert_difference("SystemModeSnapshot.count", 1) do
        snapshot = SystemModeSnapshotBuilder.new.call
      end

      assert snapshot.captured_at
      assert snapshot.health_score
      assert snapshot.pipeline_status["steps"].is_a?(Array)
      assert snapshot.integrations_summary["rows"].is_a?(Array)
      assert snapshot.visual_analytics["charts"].is_a?(Array)
      assert snapshot.metadata["status_cards"].is_a?(Array)
    end
  end
end
