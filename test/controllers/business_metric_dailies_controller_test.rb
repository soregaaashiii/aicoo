require "test_helper"

class BusinessMetricDailiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:suelog)
    @metric = BusinessMetricDaily.create!(
      business: @business,
      recorded_on: Date.current,
      impressions: 100,
      clicks: 5
    )
  end

  test "should get index" do
    get business_metric_dailies_url

    assert_response :success
    assert_includes response.body, "代理指標"
    assert_includes response.body, @business.name
    assert_includes response.body, "proxy_score"
  end

  test "should get new" do
    get new_business_metric_daily_url(business_metric_daily: { business_id: @business.id })

    assert_response :success
    assert_select "select[name='business_metric_daily[business_id]']"
  end

  test "should create business metric daily" do
    assert_difference("BusinessMetricDaily.count", 1) do
      post business_metric_dailies_url, params: {
        business_metric_daily: {
          business_id: @business.id,
          recorded_on: Date.yesterday,
          impressions: 1_000,
          clicks: 10,
          sessions: 20,
          pageviews: 30,
          phone_clicks: 1,
          map_clicks: 2,
          affiliate_clicks: 3
        }
      }
    end

    assert_redirected_to business_metric_dailies_url
  end

  test "should update business metric daily" do
    patch business_metric_daily_url(@metric), params: {
      business_metric_daily: {
        business_id: @business.id,
        recorded_on: Date.current,
        impressions: 300,
        clicks: 7
      }
    }

    assert_redirected_to business_metric_dailies_url
    assert_equal 300, @metric.reload.impressions
  end

  test "should destroy business metric daily" do
    assert_difference("BusinessMetricDaily.count", -1) do
      delete business_metric_daily_url(@metric)
    end

    assert_redirected_to business_metric_dailies_url
  end
end
