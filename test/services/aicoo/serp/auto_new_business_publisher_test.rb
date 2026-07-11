require "test_helper"

class Aicoo::Serp::AutoNewBusinessPublisherTest < ActiveSupport::TestCase
  test "auto adds serp new business candidate as visible business and public landing page" do
    source_business = businesses(:suelog)
    candidate = nil

    assert_difference("Business.real_businesses.count", 1) do
      assert_no_difference("ApprovalLog.count") do
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
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "請求前チェックリスト", candidate.business.name
    assert_equal "exploring", candidate.business.status
    assert_not candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert_equal "active", candidate.business.resource_status
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
    assert Business.real_businesses.where(id: candidate.business_id).exists?

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
    assert_equal "exploring", candidate.business.status
    assert_not candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
  end

  test "repairer restores approved serp candidate without owner approval" do
    source_business = businesses(:suelog)
    candidate = source_business.action_candidates.create!(
      title: "一時候補",
      description: "後からSERP新規事業候補へ補正する",
      action_type: "other",
      department: "general",
      generation_source: "manual",
      status: "idea",
      immediate_value_yen: 50_000,
      success_probability: 0.2,
      expected_hours: 1
    )
    candidate.update_columns(
      action_type: "build_lp",
      department: "new_business",
      generation_source: "serp",
      status: "approved",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "SERP復旧テスト事業",
        "source_query" => "SERP 復旧 テスト"
      }
    )

    assert_difference("Business.real_businesses.count", 1) do
      assert_no_difference("ApprovalLog.count") do
        result = Aicoo::ApprovedNewBusinessCandidateRepairer.call(source: "test_repair")
        assert_operator result.repaired_count, :>=, 1
        assert_equal 0, result.failed_count
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "SERP復旧テスト事業", candidate.business.name
    assert_equal "exploring", candidate.business.status
    assert Business.real_businesses.where(id: candidate.business_id).exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
  end
end
