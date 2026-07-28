require "test_helper"

module Aicoo
  class BusinessIndexCandidateLoaderTest < ActiveSupport::TestCase
    test "projected candidates preserve business expected value inputs and results" do
      business = Business.create!(
        name: "一覧候補投影テスト",
        status: "building",
        business_type: "saas"
      )
      first = business.action_candidates.create!(
        title: "投影候補1",
        action_type: "seo_improvement",
        status: "proposal",
        expected_profit_yen: 30_000,
        expected_learning_value_yen: 2_000,
        cost_yen: 500,
        success_probability: 0.8,
        metadata: {
          "unrelated_large_value" => "x" * 20_000,
          "opportunity" => {
            "key" => "同じ検索機会",
            "supporting_metrics" => {
              "impressions" => 10_000,
              "current_ctr" => 0.01,
              "benchmark_ctr" => 0.04
            }
          },
          "value_model" => {
            "raw_expected_value_yen" => 40_000,
            "confidence" => 0.75,
            "target_period" => "30d",
            "evidence" => {
              "conversion_rate" => 0.04,
              "profit_per_conversion" => 12_000
            }
          },
          "target_url" => "https://example.com/first",
          "target_url_type" => "owned",
          "cannibalization_rate" => 0.1
        }
      )
      second = business.action_candidates.create!(
        title: "投影候補2",
        action_type: "article_update",
        status: nil,
        expected_profit_yen: 20_000,
        expected_learning_value_yen: 1_000,
        cost_yen: 300,
        success_probability: 0.6,
        metadata: {
          "evidence" => {
            "query" => "別の検索機会",
            "impressions" => 5_000,
            "current_ctr" => 0.02,
            "benchmark_ctr" => 0.05,
            "conversion_rate" => 0.03
          },
          "profit_per_conversion" => 8_000,
          "action_plan" => {
            "target_url_or_identifier" => "https://example.com/second"
          },
          "target_url" => "https://example.com/second",
          "target_url_type" => "owned"
        }
      )
      business.action_candidates.create!(
        title: "除外候補",
        action_type: "seo_improvement",
        status: "done",
        expected_profit_yen: 999_999
      )

      full_candidates = business.action_candidates
        .where("status IS NULL OR status NOT IN (?)", ActionCandidate::INACTIVE_STATUSES)
        .order(:id)
        .to_a
      projected_candidates = BusinessIndexCandidateLoader.call([ business ]).fetch(business.id).sort_by(&:id)

      assert_equal [ first.id, second.id ], projected_candidates.map(&:id)
      assert_equal full_candidates.map { |candidate| candidate_values(candidate) },
        projected_candidates.map { |candidate| candidate_values(candidate) }
      assert_not projected_candidates.first.metadata.key?("unrelated_large_value")

      direct = BusinessExpectedValue.call(business, candidates: full_candidates, persist: false)
      projected = BusinessExpectedValue.call(business, candidates: projected_candidates, persist: false)

      assert_equal direct.to_h.except(:business), projected.to_h.except(:business)
    end

    test "returns no candidates for an empty business collection" do
      assert_equal({}, BusinessIndexCandidateLoader.call([]))
    end

    private

    def candidate_values(candidate)
      BusinessIndexCandidateLoader::SELECT_COLUMNS.to_h do |column|
        [ column, candidate.public_send(column) ]
      end
    end
  end
end
