require "test_helper"

module Aicoo
  class SerpLandingPageCandidateGeneratorTest < ActiveSupport::TestCase
    test "generates landing page candidates from serp results" do
      business = Business.create!(name: "SERP Candidate Business")

      result = SerpLandingPageCandidateGenerator.new(
        business:,
        keyword: "大阪 喫煙所",
        raw_text: "大阪喫煙所まとめ,https://example.com,大阪の喫煙所"
      ).call

      assert_equal "大阪 喫煙所", result.serp_analysis.keyword
      assert_equal 3, result.candidates.size
      assert result.candidates.all? { |candidate| candidate.keyword == "大阪 喫煙所" }
      assert result.candidates.all? { |candidate| candidate.expected_value_score.to_d.positive? }
      assert result.candidates.first.competition_note.include?("競合強度")
    end
  end
end
