require "test_helper"

class Aicoo::Serp::AutoNewBusinessPublisherTest < ActiveSupport::TestCase
  test "publishes serp new business candidate as business and public landing page" do
    source_business = businesses(:suelog)
    candidate = source_business.action_candidates.create!(
      title: "新規事業候補: 請求前チェックリスト",
      description: "SERPから請求前チェックリストの需要を見つけた。",
      action_type: "build_lp",
      department: "new_business",
      generation_source: "integrated_decision",
      status: "idea",
      immediate_value_yen: 80_000,
      success_probability: 0.3,
      expected_hours: 2,
      execution_prompt: "LP検証を行う。",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "請求前チェックリスト",
        "source_query" => "請求前 チェックリスト",
        "problem" => "請求前のミスを減らしたい",
        "target_customer" => "フリーランス",
        "revenue_model" => "テンプレート販売"
      }
    )

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "請求前チェックリスト", candidate.business.name
    assert candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")

    assert_no_difference -> { Business.real_businesses.count } do
      assert_no_difference -> { AicooLabLandingPage.publicly_available.count } do
        result = Aicoo::Serp::AutoNewBusinessPublisher.call(candidates: [ candidate ])
        assert_equal 0, result.business_created_count
        assert_equal 0, result.lp_published_count
        assert_equal 0, result.failed_count
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "請求前チェックリスト", candidate.business.name
    assert candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
  end
end
