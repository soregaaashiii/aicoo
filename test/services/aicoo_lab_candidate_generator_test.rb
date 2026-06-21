require "test_helper"

class AicooLabCandidateGeneratorTest < ActiveSupport::TestCase
  test "generates ten rule based candidates" do
    assert_difference("AicooLabGenerationRun.count") do
      @result = AicooLabCandidateGenerator.new(count: 10).call
    end
    result = @result

    assert_equal 10, result.created_candidates.size
    assert_equal AicooLabGenerationRun.last, result.generation_run
    assert_equal "candidate_generation", result.generation_run.generation_type
    assert_equal "succeeded", result.generation_run.status
    assert_equal 10, result.generation_run.generated_count
    assert_includes result.generation_run.prompt, "Rule based AICOO Lab candidate generation"
    assert_includes result.generation_run.response, result.created_candidates.first.title
    assert_equal 10, AicooLabExperimentCandidate.where(generation_source: "rule_based").count
    assert result.created_candidates.all? { |candidate| candidate.status == "proposed" }
  end

  test "does not create active duplicate titles" do
    title = AicooLabCandidateGenerator::CANDIDATE_SPECS.first.fetch(:title)
    AicooLabExperimentCandidate.create!(
      AicooLabCandidateGenerator::CANDIDATE_SPECS.first.merge(status: "proposed", generation_source: "manual")
    )

    result = AicooLabCandidateGenerator.new(count: 10).call

    assert_equal 10, result.created_candidates.size
    assert_equal 1, AicooLabExperimentCandidate.where(title:).count
  end

  test "generated candidates include required attributes" do
    candidate = AicooLabCandidateGenerator.new(count: 1).call.created_candidates.first

    assert candidate.title.present?
    assert candidate.description.present?
    assert candidate.experiment_type.present?
    assert candidate.market_category.present?
    assert candidate.acquisition_channel.present?
    assert_not_nil candidate.expected_90d_profit_yen
    assert_not_nil candidate.success_probability
    assert_not_nil candidate.budget_yen
    assert_not_nil candidate.estimated_work_minutes
    assert_not_nil candidate.assumed_price_yen
    assert_not_nil candidate.lp_word_count
    assert_not_nil candidate.cta_count
    assert candidate.rationale.present?
    assert candidate.target_user.present?
    assert candidate.problem_statement.present?
    assert candidate.hypothesis.present?
    assert candidate.validation_method.present?
    assert candidate.expected_learning.present?
    assert candidate.rejection_condition.present?
    assert_equal "rule_based", candidate.generation_source
    assert candidate.lab_priority_score.present?
  end
end
