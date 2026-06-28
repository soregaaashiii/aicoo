require "test_helper"

class GoogleApiImportRunTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:suelog)
  end

  test "uses full 28 days before first successful import" do
    assert_equal 28, GoogleApiImportRun.next_fetch_days_for(@business, today: Date.new(2026, 6, 28))
  end

  test "uses days since latest successful end date for incremental imports" do
    GoogleApiImportRun.create!(
      business: @business,
      status: "success",
      source_types: %w[gsc ga4],
      fetched_days: 28,
      started_at: Time.zone.local(2026, 6, 25, 9),
      finished_at: Time.zone.local(2026, 6, 25, 9, 1),
      metadata: { "end_date" => "2026-06-25" }
    )

    assert_equal 3, GoogleApiImportRun.next_fetch_days_for(@business, today: Date.new(2026, 6, 28))
  end

  test "full fetch override uses 28 days" do
    GoogleApiImportRun.create!(
      business: @business,
      status: "success",
      source_types: %w[gsc],
      fetched_days: 1,
      started_at: Time.current,
      finished_at: Time.current,
      metadata: { "end_date" => Date.yesterday.to_s }
    )

    assert_equal 28, GoogleApiImportRun.next_fetch_days_for(@business, full_fetch: true)
  end
end
