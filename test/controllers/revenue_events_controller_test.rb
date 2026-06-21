require "test_helper"

class RevenueEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:suelog)
    @revenue_event = RevenueEvent.create!(
      business: @business,
      occurred_on: Date.current,
      event_type: "revenue",
      amount: 500
    )
  end

  test "should get index" do
    get revenue_events_url

    assert_response :success
    assert_includes response.body, "収益記録"
    assert_includes response.body, @business.name
    assert_includes response.body, "売上"
  end

  test "should get new" do
    get new_revenue_event_url(revenue_event: { business_id: @business.id })

    assert_response :success
    assert_select "select[name='revenue_event[business_id]']"
  end

  test "should create revenue event" do
    assert_difference("RevenueEvent.count", 1) do
      post revenue_events_url, params: {
        revenue_event: {
          business_id: @business.id,
          occurred_on: Date.current,
          event_type: "expense",
          amount: 3_000
        }
      }
    end

    event = RevenueEvent.order(:created_at).last
    assert_redirected_to revenue_events_url
    assert_equal "expense", event.event_type
    assert_equal 3_000, event.amount
  end

  test "should update revenue event" do
    patch revenue_event_url(@revenue_event), params: {
      revenue_event: {
        business_id: @business.id,
        occurred_on: Date.current,
        event_type: "expense",
        amount: 900
      }
    }

    assert_redirected_to revenue_events_url
    @revenue_event.reload
    assert_equal "expense", @revenue_event.event_type
    assert_equal 900, @revenue_event.amount
  end

  test "should destroy revenue event" do
    assert_difference("RevenueEvent.count", -1) do
      delete revenue_event_url(@revenue_event)
    end

    assert_redirected_to revenue_events_url
  end
end
