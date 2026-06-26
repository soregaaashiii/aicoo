require "test_helper"

class OpportunityDiscoveryItemTest < ActiveSupport::TestCase
  test "sets defaults" do
    item = OpportunityDiscoveryItem.create!(title: "Owner insight")

    assert_equal "owner_discovery", item.source_type
    assert_equal "new", item.status
    assert_equal 50, item.opportunity_score
    assert item.discovered_at.present?
    assert item.strategic_score.present?
    assert item.decision_log_coefficient.present?
  end

  test "converts to action candidate" do
    item = OpportunityDiscoveryItem.create!(
      business: businesses(:suelog),
      title: "表示回数が多い記事を伸ばす",
      description: "CTR改善より儲かるかもしれない",
      opportunity_score: 80
    )

    assert_difference("ActionCandidate.count", 1) do
      candidate = item.convert_to_action_candidate!
      assert_equal "opportunity_validation", candidate.action_type
      assert_equal "opportunity_discovery", candidate.generation_source
      assert_equal "converted", item.reload.status
      assert_equal item.id, candidate.metadata["opportunity_id"]
    end
  end

  test "does not convert new service opportunity without business" do
    item = OpportunityDiscoveryItem.create!(
      title: "新規サービス候補",
      description: "既存事業に紐づかない仮説",
      opportunity_score: 80
    )

    assert_no_difference("ActionCandidate.count") do
      assert_nil item.convert_to_action_candidate!
    end

    assert item.reload.new_service_candidate?
    assert item.practicality_warning?
    assert_equal true, item.metadata["business_creation_required"]
  end

  test "creates business draft for new service opportunity before conversion" do
    item = OpportunityDiscoveryItem.create!(
      title: "新しい予約比較サービス",
      description: "予約導線の比較需要がありそう",
      opportunity_score: 80
    )

    assert_difference("Business.count", 1) do
      business = Aicoo::OpportunityBusinessBuilder.new(item).call
      assert_equal "idea", business.status
      assert_equal business, item.reload.business
      assert_equal "approved", item.status
    end

    assert_difference("ActionCandidate.count", 1) do
      assert item.convert_to_action_candidate!
    end
  end

  test "business draft creation is idempotent" do
    item = OpportunityDiscoveryItem.create!(title: "重複しない新規サービス", opportunity_score: 80)
    builder = Aicoo::OpportunityBusinessBuilder.new(item)

    assert_difference("Business.count", 1) do
      builder.call
    end

    assert_no_difference("Business.count") do
      builder.call
    end
  end

  test "stores strategic learning scores" do
    item = OpportunityDiscoveryItem.create!(
      title: "外部シグナルからLP検証",
      source_type: "google_trends",
      opportunity_type: "lp_test",
      opportunity_score: 90,
      expected_value_yen: 80_000,
      confidence: 85
    )

    assert item.long_term_profit_score.present?
    assert item.learning_value_score.present?
    assert item.exploration_value_score.present?
    assert item.strategic_adjusted_score.present?
    assert item.metadata.dig("strategic_learning", "strategic_score").present?
    assert item.metadata.dig("strategic_learning_guardrail", "clamped_adjusted_score").present?
    assert item.practicality_score.present?
    assert item.metadata.dig("practicality", "subscores").present?
  end

  test "stores business playbook score for opportunity" do
    BusinessPlaybook.create!(
      business: businesses(:suelog),
      sample_count: 20,
      confidence_score: 80,
      opportunity_type_summary: {
        "lp_test" => {
          "type" => "lp_test",
          "score" => "75",
          "sample_count" => 20
        }
      }
    )
    item = OpportunityDiscoveryItem.create!(
      business: businesses(:suelog),
      title: "LP検証Opportunity",
      source_type: "google_trends",
      opportunity_type: "lp_test",
      opportunity_score: 90
    )

    assert_equal 75.to_d, item.business_playbook_score
    assert item.metadata.dig("business_playbook", "coefficient").present?
  end
end
