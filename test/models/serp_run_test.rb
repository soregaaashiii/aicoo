require "test_helper"

class SerpRunTest < ActiveSupport::TestCase
  test "finishes from scan result as success" do
    run = SerpRun.create!(status: "running", started_at: Time.current, executed_by: "manual")
    result = Aicoo::Serp::ScanRunner::Result.new(
      started_at: run.started_at,
      finished_at: Time.current,
      provider: "serper",
      target_business_count: 1,
      query_count: 1,
      success_count: 1,
      failed_count: 0,
      result_count: 10,
      duration_seconds: 1.1,
      estimated_cost_yen: 3,
      limit: 10,
      scan_batch_id: "batch",
      analyses: []
    )

    run.finish_from_result!(result)

    assert_equal "success", run.status
    assert_equal 1, run.query_count
    assert_equal 1, run.success_count
    assert_equal 0, run.failure_count
    assert_equal 3, run.credit_estimate
  end
end
