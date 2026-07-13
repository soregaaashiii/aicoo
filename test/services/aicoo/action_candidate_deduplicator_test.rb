require "test_helper"

module Aicoo
  class ActionCandidateDeduplicatorTest < ActiveSupport::TestCase
    test "dry run reports duplicates without changing records" do
      first, second = create_duplicate_candidates

      result = Aicoo::ActionCandidateDeduplicator.call(apply: false)

      assert_operator result.duplicates, :>=, 1
      assert_includes result.candidate_ids, first.id
      assert_includes result.candidate_ids, second.id
      assert_equal "idea", second.reload.status
    end

    test "apply archives duplicate and keeps canonical action" do
      first, second = create_duplicate_candidates(first_value: 10_000, second_value: 30_000)

      result = Aicoo::ActionCandidateDeduplicator.call(apply: true)

      assert_operator result.merged, :>=, 1
      assert_equal "archived", first.reload.status
      assert_equal "idea", second.reload.status
      assert_includes second.metadata["duplicate_candidate_ids"], first.id
      assert_equal second.id, first.metadata["duplicate_of_action_candidate_id"]
    end

    test "does not merge different work for same opportunity" do
      business = businesses(:suelog)
      article = create_candidate(
        business:,
        title: "吸えログ比較記事を1本作成する",
        action_type: "new_article_candidate",
        task: "吸えログ比較記事を1本作成する"
      )
      title_fix = create_candidate(
        business:,
        title: "吸えログ比較ページのtitle/metaを改善する",
        action_type: "seo_improvement",
        task: "吸えログ比較ページのtitle/metaを改善する"
      )

      result = Aicoo::ActionCandidateDeduplicator.call(apply: true)

      assert_not_includes result.candidate_ids, article.id
      assert_not_includes result.candidate_ids, title_fix.id
      assert_equal "idea", article.reload.status
      assert_equal "idea", title_fix.reload.status
    end

    private

    def create_duplicate_candidates(first_value: 10_000, second_value: 20_000)
      business = businesses(:suelog)
      [
        create_candidate(business:, title: "吸えログ比較記事を1本作成する", value: first_value),
        create_candidate(business:, title: "吸えログ比較記事を1本作成する", value: second_value)
      ]
    end

    def create_candidate(business:, title:, action_type: "new_article_candidate", task: title, value: 10_000)
      ActionCandidate.create!(
        business:,
        title:,
        description: "検索需要に対応する記事を作る",
        action_type:,
        generation_source: "business_analyzer",
        department: "revenue",
        status: "idea",
        immediate_value_yen: value,
        success_probability: 0.4,
        expected_hours: 2,
        metadata: {
          "opportunity_key" => "gsc:query:suelog-comparison",
          "source_query" => "吸えログ 比較",
          "concrete_task" => task,
          "execution_mode" => "content_creation"
        }
      )
    end
  end
end
