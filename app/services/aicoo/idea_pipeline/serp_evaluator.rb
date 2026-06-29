module Aicoo
  module IdeaPipeline
    class SerpEvaluator
      MIN_SCORE_FOR_SERP = 60

      def initialize(item, provider: nil, limit: nil)
        @item = item
        @provider = (provider.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
        @limit = limit.to_i.positive? ? limit.to_i : Aicoo::Serp::ScanPlan.configured_limit
      end

      def call
        return mark_skipped!("final_scoreが低いためSERPを実行しません。") if item.final_score.to_d < MIN_SCORE_FOR_SERP

        mark_running!
        result = Aicoo::Serp::Adapter.call(
          provider: provider.to_sym,
          type: :google_search,
          query: search_query,
          location: "Japan",
          language: "ja",
          limit:
        )
        update_from_result(result.to_h)
      rescue Aicoo::Serp::MissingApiKeyError => e
        mark_blocked!(e.message)
      rescue Aicoo::Serp::Error => e
        mark_failed!(e.message)
      end

      private

      attr_reader :item, :provider, :limit

      def mark_running!
        item.update!(status: "serp_running", current_stage: "serp")
      end

      def search_query
        item.metadata.to_h.dig("serp", "query").presence ||
          [ item.title, item.target_user.to_s.split(/[。.\n]/).first ].compact_blank.join(" ")
      end

      def update_from_result(payload)
        organic = Array(payload["organic_results"])
        related = Array(payload["related_searches"])
        paa = Array(payload["people_also_ask"])
        competition_strength = [ organic.size * 8, 100 ].min
        market_signal = [ organic.size * 5 + related.size * 7 + paa.size * 6, 100 ].min
        differentiation = [ [ 100 - competition_strength + item.automation_score.to_d * 0.2, 0 ].max, 100 ].min
        passed = item.final_score.to_d >= 65 && market_signal >= 20 && competition_strength <= 85

        item.update!(
          status: "serp_evaluated",
          current_stage: "serp",
          serp_evaluated_at: Time.current,
          serp_snapshot: {
            "status" => "success",
            "passed" => passed,
            "provider" => payload["provider"],
            "query" => payload["query"],
            "limit" => limit,
            "organic_count" => organic.size,
            "related_count" => related.size,
            "people_also_ask_count" => paa.size,
            "competition_strength" => competition_strength,
            "market_signal" => market_signal,
            "differentiation_score" => differentiation.round(2),
            "top_results" => organic.first(5),
            "related_searches" => related.first(10),
            "people_also_ask" => paa.first(5),
            "evaluated_at" => Time.current.iso8601
          }
        )
        item
      end

      def mark_skipped!(message)
        item.update!(
          status: "serp_skipped",
          current_stage: "serp",
          serp_evaluated_at: Time.current,
          serp_snapshot: {
            "status" => "skipped",
            "passed" => false,
            "reason" => message,
            "cost_optimization" => true,
            "evaluated_at" => Time.current.iso8601
          }
        )
        item
      end

      def mark_blocked!(message)
        item.update!(
          status: "serp_not_configured",
          current_stage: "serp",
          serp_snapshot: {
            "status" => "blocked",
            "passed" => false,
            "reason" => message,
            "provider" => provider,
            "query" => search_query,
            "evaluated_at" => Time.current.iso8601
          }
        )
        item
      end

      def mark_failed!(message)
        item.update!(
          status: "serp_blocked",
          current_stage: "serp",
          serp_snapshot: {
            "status" => "failed",
            "passed" => false,
            "reason" => message,
            "provider" => provider,
            "query" => search_query,
            "evaluated_at" => Time.current.iso8601
          }
        )
        item
      end
    end
  end
end
