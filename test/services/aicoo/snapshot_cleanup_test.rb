require "test_helper"

module Aicoo
  class SnapshotCleanupTest < ActiveSupport::TestCase
    setup do
      AicooDataSnapshot.delete_all
    end

    test "archives older duplicate metric snapshots without deleting history" do
      older = create_metric_snapshot(captured_at: Time.zone.local(2026, 7, 18, 9, 0, 0))
      newer = create_metric_snapshot(captured_at: Time.zone.local(2026, 7, 18, 10, 0, 0))

      result = SnapshotCleanup.call(apply: false)
      assert_equal "dry-run", result.mode
      assert_equal 2, result.checked_count
      assert_equal 1, result.archived_count
      assert_equal [ older.id ], result.archived_snapshot_ids
      assert_nil older.reload.payload["snapshot_status"]

      assert_no_difference("AicooDataSnapshot.count") do
        apply_result = SnapshotCleanup.call(apply: true)
        assert_equal "apply", apply_result.mode
        assert_equal 1, apply_result.archived_count
      end

      assert_equal "archived", older.reload.payload["snapshot_status"]
      assert_equal "duplicate_metric_snapshot", older.payload["archived_reason"]
      assert_equal newer.id, older.payload["active_snapshot_id"]
      assert_equal "active", newer.reload.payload["snapshot_status"]
    end

    test "ignores snapshots already archived when calculating duplicates" do
      create_metric_snapshot(captured_at: Time.zone.local(2026, 7, 18, 9, 0, 0), status: "archived")
      create_metric_snapshot(captured_at: Time.zone.local(2026, 7, 18, 10, 0, 0))

      result = SnapshotCleanup.call(apply: false)

      assert_equal 0, result.archived_count
      assert_equal 0, result.duplicate_group_count
      assert_equal 1, result.already_archived_count
    end

    private

    def create_metric_snapshot(captured_at:, status: nil)
      payload = {
        "source_type" => "gsc",
        "business_id" => "2",
        "analytics_site_id" => "10",
        "domain" => "suelog.jp",
        "rows" => [
          {
            "date" => "2026-07-18",
            "page" => "/articles/umeda-smoking-cafe",
            "query" => "梅田 喫煙 カフェ",
            "clicks" => 3,
            "impressions" => 30
          }
        ],
        "snapshot_fingerprint" => "same-fingerprint",
        "snapshot_fingerprint_version" => "metric_rows_v1"
      }
      payload["snapshot_status"] = status if status

      AicooDataSnapshot.create!(
        source_type: "gsc",
        source_id: rand(1_000..9_999),
        captured_at:,
        payload:
      )
    end
  end
end
