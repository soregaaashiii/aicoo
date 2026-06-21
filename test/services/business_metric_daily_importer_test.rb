require "test_helper"

class BusinessMetricDailyImporterTest < ActiveSupport::TestCase
  test "imports gsc and ga4 snapshots into one daily metric" do
    business = businesses(:suelog)
    date = Date.current
    create_snapshot(
      source_type: "gsc",
      business:,
      date:,
      metrics: { impressions: 1_000, clicks: 25 }
    )
    create_snapshot(
      source_type: "ga4",
      business:,
      date:,
      metrics: { sessions: 80, page_views: 120 }
    )

    result = BusinessMetricDailyImporter.new(business:, date:).call
    metric = result.metric

    assert_equal business, metric.business
    assert_equal date, metric.recorded_on
    assert_equal 1_000, metric.impressions
    assert_equal 25, metric.clicks
    assert_equal 80, metric.sessions
    assert_equal 120, metric.pageviews
    assert_equal 175.0, metric.proxy_score
  end

  test "does not create duplicate record for same business and date" do
    business = businesses(:suelog)
    date = Date.current
    create_snapshot(source_type: "gsc", business:, date:, metrics: { impressions: 100, clicks: 5 })

    assert_difference("BusinessMetricDaily.count", 1) do
      BusinessMetricDailyImporter.new(business:, date:).call
      BusinessMetricDailyImporter.new(business:, date:).call
    end

    metric = BusinessMetricDaily.find_by!(business:, recorded_on: date)
    assert_equal 100, metric.impressions
    assert_equal 5, metric.clicks
  end

  test "does not fail when gsc ga4 and lp snapshots are missing" do
    business = businesses(:suelog)

    result = BusinessMetricDailyImporter.new(business:, date: Date.current).call

    assert_predicate result.metric, :persisted?
    assert_equal 0, result.metric.impressions
    assert_equal 0, result.metric.clicks
    assert_equal 0, result.metric.sessions
    assert_equal 0, result.metric.pageviews
    assert_equal 0, result.metric.proxy_score
  end

  test "imports lp event values when snapshot is tied to business" do
    business = businesses(:suelog)
    date = Date.current
    AicooDataSnapshot.create!(
      source_type: "landing_page",
      source_id: 1,
      captured_at: date.noon,
      payload: {
        business_id: business.id,
        phone_clicks: 2,
        map_clicks: 3,
        affiliate_clicks: 4
      }
    )

    metric = BusinessMetricDailyImporter.new(business:, date:).call.metric

    assert_equal 2, metric.phone_clicks
    assert_equal 3, metric.map_clicks
    assert_equal 4, metric.affiliate_clicks
  end

  test "imports all businesses for a date" do
    date = Date.current

    results = BusinessMetricDailyImporter.import_all!(date:)

    assert_equal Business.count, results.size
  end

  test "imports range into multiple daily metrics from dated snapshot rows" do
    business = businesses(:suelog)
    start_date = Date.new(2026, 6, 18)
    end_date = Date.new(2026, 6, 19)
    create_snapshot(
      source_type: "gsc",
      business:,
      date: end_date,
      payload: {
        business_id: business.id,
        rows: [
          { date: start_date.to_s, impressions: 100, clicks: 5 },
          { date: end_date.to_s, impressions: 200, clicks: 8 }
        ]
      }
    )

    results = BusinessMetricDailyImporter.import_range!(business:, start_date:, end_date:)

    assert_equal 2, results.size
    first_metric = BusinessMetricDaily.find_by!(business:, recorded_on: start_date)
    second_metric = BusinessMetricDaily.find_by!(business:, recorded_on: end_date)
    assert_equal 100, first_metric.impressions
    assert_equal 5, first_metric.clicks
    assert_equal 200, second_metric.impressions
    assert_equal 8, second_metric.clicks
  end

  test "importing same range twice does not create duplicate records" do
    business = businesses(:suelog)
    start_date = Date.new(2026, 6, 18)
    end_date = Date.new(2026, 6, 19)
    create_snapshot(
      source_type: "ga4",
      business:,
      date: end_date,
      payload: {
        business_id: business.id,
        rows: [
          { date: start_date.to_s, sessions: 10, page_views: 20 },
          { date: end_date.to_s, sessions: 15, page_views: 30 }
        ]
      }
    )

    assert_difference("BusinessMetricDaily.count", 2) do
      BusinessMetricDailyImporter.import_range!(business:, start_date:, end_date:)
      BusinessMetricDailyImporter.import_range!(business:, start_date:, end_date:)
    end
  end

  test "snapshot rows without date use captured date as fallback" do
    business = businesses(:suelog)
    date = Date.new(2026, 6, 21)
    create_snapshot(
      source_type: "ga4",
      business:,
      date:,
      payload: {
        business_id: business.id,
        rows: [
          { sessions: 10, page_views: 20 }
        ]
      }
    )

    metric = BusinessMetricDailyImporter.new(business:, date:).call.metric

    assert_equal 10, metric.sessions
    assert_equal 20, metric.pageviews
  end

  private

  def create_snapshot(source_type:, business:, date:, metrics: nil, payload: nil)
    AicooDataSnapshot.create!(
      source_type:,
      source_id: AicooDataSnapshot.maximum(:source_id).to_i + 1,
      captured_at: date.noon,
      payload: payload || {
        business_id: business.id,
        metrics:
      }
    )
  end
end
