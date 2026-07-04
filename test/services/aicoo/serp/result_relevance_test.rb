require "test_helper"

module Aicoo
  module Serp
    class ResultRelevanceTest < ActiveSupport::TestCase
      test "filters unrelated log-management results from suelog branded query" do
        scorer = ResultRelevance.new(business: businesses(:suelog), query: "吸えログ 比較")
        results = [
          { "title" => "ログ管理システム比較", "url" => "https://example.com/log", "snippet" => "操作ログと監査ログを比較できます" },
          { "title" => "大阪 喫煙可能 カフェ 比較", "url" => "https://example.com/smoking", "snippet" => "梅田で喫煙可の飲食店を探せます" }
        ]

        scored = scorer.scored_results(results)
        relevant = scorer.relevant_results(results)

        assert scorer.branded_query?
        assert scored.first.excluded
        assert_includes scored.first.reason, "Business領域外"
        assert_equal [ "大阪 喫煙可能 カフェ 比較" ], relevant.map { |row| row["title"] }
      end
    end
  end
end
