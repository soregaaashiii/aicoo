require "test_helper"

module Aicoo
  class BusinessPlaybookScorerTest < ActiveSupport::TestCase
    test "returns neutral score for new business without playbook" do
      candidate = ActionCandidate.new(
        business: businesses(:suelog),
        title: "New candidate",
        action_type: "seo_improvement"
      )

      result = BusinessPlaybookScorer.new(candidate).call

      assert_equal 50.to_d, result.score
      assert_equal 1.to_d, result.coefficient
    end

    test "scores candidate from learned action type" do
      business = businesses(:suelog)
      BusinessPlaybook.create!(
        business:,
        sample_count: 20,
        confidence_score: 80,
        action_type_summary: {
          "seo_improvement" => {
            "type" => "seo_improvement",
            "score" => "80",
            "sample_count" => 20
          }
        }
      )
      candidate = ActionCandidate.new(
        business:,
        title: "SEO candidate",
        action_type: "seo_improvement"
      )

      result = BusinessPlaybookScorer.new(candidate).call

      assert_equal 80.to_d, result.score
      assert_operator result.coefficient, :>, 1
      assert_operator result.coefficient, :<=, 1.12.to_d
    end
  end
end
