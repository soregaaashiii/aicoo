require "test_helper"

module Aicoo
  class SystemModeSnapshotPresenterTest < ActiveSupport::TestCase
    test "presents latest snapshot without running live monitor" do
      snapshot = SystemModeSnapshotBuilder.new.call
      result = SystemModeSnapshotPresenter.new(snapshot:).call

      assert_equal true, result.snapshot_present
      assert_equal snapshot.captured_at.to_i, result.snapshot_captured_at.to_i
      assert result.status_cards.any?
      assert result.pipeline_steps.any?
      assert result.charts.any?
    end

    test "returns lightweight fallback when snapshot is missing" do
      result = SystemModeSnapshotPresenter.new(snapshot: nil).call

      assert_equal false, result.snapshot_present
      assert_equal "Snapshot未作成", result.snapshot_warning
      assert_empty result.integration_rows
      assert_empty result.charts
    end

    test "warns when snapshot is stale" do
      snapshot = SystemModeSnapshotBuilder.new.call(captured_at: 2.days.ago)
      result = SystemModeSnapshotPresenter.new(snapshot:).call

      assert_equal true, result.snapshot_present
      assert_equal "Snapshotが古くなっています。", result.snapshot_warning
      assert_includes result.system_health_message, "Snapshotが古くなっています。"
    end
  end
end
