require "test_helper"

module Aicoo
  class ActivityEventEntryDiagnosticTest < ActiveSupport::TestCase
    test "reports an API-ingested shop event reaching BusinessActivityLog record" do
      business = businesses(:suelog)
      activity_log = BusinessActivityLog.record!(
        business:,
        attributes: {
          source_app: "suelog",
          activity_type: "shop_created",
          resource_type: "Shop",
          resource_id: "diagnostic-shop",
          title: "店舗を追加",
          occurred_at: Time.current,
          source_method: "logger",
          idempotency_key: "activity-event-entry-diagnostic"
        }
      )

      SuelogRecord.stub(:configured?, false) do
        result = ActivityEventEntryDiagnostic.new(business_id: business.id).call
        row = result.rows.find { |candidate| candidate.event_type == "shop_created" }

        assert row.callback_called
        assert row.activity_log_record_called
        assert row.business_activity_log_created
        assert row.activity_api_sent
        assert_nil row.skip_reason
        assert_operator result.summary.record_call_count, :>=, 1
        assert_operator result.summary.activity_api_count, :>=, 1
      end

      assert_equal activity_log, BusinessActivityLog.find(activity_log.id)
    end

    test "reports the source database as the blocking reason when it is unavailable" do
      business = businesses(:suelog)

      SuelogRecord.stub(:configured?, false) do
        result = ActivityEventEntryDiagnostic.new(business_id: business.id).call
        row = result.rows.find { |candidate| candidate.event_type == "article_updated" }

        refute row.record_saved
        refute row.business_activity_log_created
        assert_equal "source_database_unavailable", row.skip_reason
        refute result.summary.source_database_available
      end
    end
  end
end
