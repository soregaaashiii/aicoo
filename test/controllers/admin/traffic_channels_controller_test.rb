require "test_helper"

module Admin
  class TrafficChannelsControllerTest < ActionDispatch::IntegrationTest
    setup do
      DataSourceCostProfile.ensure_defaults!
    end

    test "shows traffic channel center" do
      get admin_traffic_channels_url

      assert_response :success
      assert_includes response.body, "Traffic Channel Center"
      assert_includes response.body, "Overview"
      assert_includes response.body, "Channel設定"
      assert_includes response.body, "Business設定"
      assert_includes response.body, "実行履歴"
      assert_includes response.body, "成果分析"
      assert_includes response.body, "SERP設定へ"
    end

    test "serp row uses serp runs instead of traffic channel runs" do
      Aicoo::Serp::Scheduler.update!("scheduler_enabled" => true)
      started_at = Time.zone.local(2026, 7, 2, 8, 0)
      travel_to started_at do
        SerpRun.create!(
          status: "success",
          started_at:,
          finished_at: started_at + 2.minutes,
          executed_by: "scheduler",
          query_count: 12,
          success_count: 12,
          failure_count: 0,
          candidate_count: 3,
          credit_estimate: 12
        )

        get admin_traffic_channels_url
      end

      assert_response :success
      assert_select "tr#traffic-channel-serp" do |row|
        html = row.to_s
        assert_includes html, "Scheduler ON"
        assert_includes html, "latest: scheduler"
        assert_includes html, "12回"
        assert_includes html, "0件"
        assert_includes html, "SERP設定"
        assert_not_includes html, "未実行"
      end
    end

    test "updates global channel enabled state" do
      patch admin_traffic_channel_url("x"), params: { traffic_channel: { enabled: "0" } }

      assert_redirected_to admin_traffic_channels_url(anchor: "traffic-channel-settings")
      assert_not DataSourceCostProfile.find_by!(source_key: "x").enabled?
    end

    test "updates business channel enabled state" do
      business = businesses(:suelog)

      patch admin_business_traffic_channel_url("reddit", business), params: { traffic_channel: { enabled: "0" } }

      assert_redirected_to admin_traffic_channels_url(anchor: "traffic-business-settings")
      setting = BusinessDataSourceSetting.find_by!(business:, source_key: "reddit")
      assert_not setting.enabled?
    end

    test "creates traffic channel action candidate" do
      business = businesses(:suelog)

      assert_difference "ActionCandidate.where(generation_source: 'traffic_channel').count", 1 do
        post admin_traffic_channel_action_candidate_url("note", business)
      end

      candidate = ActionCandidate.order(:created_at).last
      assert_redirected_to action_candidate_url(candidate)
      assert_equal business, candidate.business
      assert_equal "traffic_channel", candidate.generation_source
      assert_equal "note", candidate.metadata["channel_key"]
    end
  end
end
