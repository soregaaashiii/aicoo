require "test_helper"

module Admin
  class SerpRunsControllerTest < ActionDispatch::IntegrationTest
    test "shows run plan rows and skip reasons" do
      business = businesses(:suelog)
      run = SerpRun.create!(
        status: "success",
        executed_by: "manual",
        started_at: Time.current,
        finished_at: Time.current,
        query_count: 1,
        success_count: 1,
        failure_count: 0,
        metadata: {
          "plan" => {
            "rows" => [
              {
                "business_id" => business.id,
                "business_name" => business.name,
                "serp_query_id" => 123,
                "query" => "梅田 喫煙",
                "status" => "run",
                "reason" => "priority_selected"
              },
              {
                "business_id" => business.id,
                "business_name" => business.name,
                "serp_query_id" => 124,
                "query" => "難波 喫煙",
                "status" => "skip",
                "reason" => "global_daily_limit"
              }
            ]
          }
        }
      )

      get admin_serp_run_url(run)

      assert_response :success
      assert_includes response.body, "SERP Run ##{run.id}"
      assert_includes response.body, "梅田 喫煙"
      assert_includes response.body, "難波 喫煙"
      assert_includes response.body, "global_daily_limit"
    end
  end
end
