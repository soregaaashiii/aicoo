require "test_helper"

class CorrectionReadinessActionCandidateGeneratorTest < ActiveSupport::TestCase
  test "generates action candidates for businesses with missing correction data" do
    result = CorrectionReadinessActionCandidateGenerator.generate_all!

    assert_operator result.created.size, :>, 0
    candidate = result.created.first
    assert_equal "data_preparation", candidate.action_type
    assert_equal "ai_business", candidate.generation_source
    assert_equal "correction_readiness", candidate.metadata.fetch("metric_rule")
    assert_includes candidate.metadata.fetch("missing_type"), "action_results"
    assert_equal candidate.business_id, candidate.metadata.fetch("business_id")
    assert candidate.metadata.fetch("required_count").fetch("action_results").positive?
    assert candidate.metadata.fetch("current_count").key?("action_results")
    assert_includes candidate.evaluation_reason, "予測精度を上げるための学習データ"
    assert_includes candidate.execution_prompt, "実行済みの行動候補を"
  end

  test "does not generate duplicate candidate within seven days" do
    business = businesses(:suelog)
    business.action_candidates.create!(
      title: "#{business.name}の予測精度に必要な学習データを増やす",
      action_type: "data_preparation",
      generation_source: "ai_business",
      created_at: Time.current
    )

    assert_no_difference("business.action_candidates.count") do
      CorrectionReadinessActionCandidateGenerator.generate_all!
    end
  end
end
