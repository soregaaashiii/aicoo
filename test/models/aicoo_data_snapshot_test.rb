require "test_helper"

class AicooDataSnapshotTest < ActiveSupport::TestCase
  test "creates snapshot with defaults" do
    snapshot = AicooDataSnapshot.create!(
      source_type: "landing_page",
      source_id: 1,
      payload: { pv: 10 }
    )

    assert_predicate snapshot, :persisted?
    assert_not_nil snapshot.captured_at
    assert_equal({ "pv" => 10 }, snapshot.payload)
  end

  test "validates source type" do
    snapshot = AicooDataSnapshot.new(source_type: "judge", source_id: 1)

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:source_type], "is not included in the list"
  end
end
