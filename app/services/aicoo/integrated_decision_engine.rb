module Aicoo
  class IntegratedDecisionEngine
    Summary = Data.define(
      :serp_run,
      :daily_run,
      :top_business,
      :candidate_count,
      :expected_profit_yen,
      :message
    )

    def initialize(serp_run: SerpRun.recent.first, daily_run: AicooDailyRun.recent.first)
      @serp_run = serp_run
      @daily_run = daily_run
    end

    def summary
      business = top_business
      Summary.new(
        serp_run:,
        daily_run:,
        top_business: business,
        candidate_count: integrated_candidates.count,
        expected_profit_yen: integrated_candidates.maximum(:expected_profit_yen).to_i,
        message: message_for(business)
      )
    end

    def generate_unified_candidates!
      return [] unless serp_run&.successful? || serp_run&.status == "partial_failed"

      candidates = []
      serp_run.serp_analyses.successful.includes(:business).group_by(&:business).each do |business, analyses|
        next unless business
        next if duplicate_today?(business)

        best_analysis = analyses.max_by { |analysis| analysis.result_count.to_i }
        candidates << business.action_candidates.create!(
          title: "#{business.name}の市場観測と内部データを統合して改善する",
          description: "SERP市場観測とDaily Runの内部データを合わせ、検索意図・CTR・CV・改善履歴を見て優先改善を決めます。",
          action_type: "seo_improvement",
          department: "revenue",
          generation_source: "integrated_decision",
          status: "idea",
          immediate_value_yen: 20_000,
          success_probability: 0.35,
          expected_hours: 1.5,
          confidence_score: 45,
          data_confidence_score: 50,
          priority_score: 65,
          execution_prompt: prompt_for(business, best_analysis),
          evaluation_reason: "integrated_decision:serp_and_daily",
          metadata: {
            "source" => "integrated_decision",
            "serp_run_id" => serp_run.id,
            "aicoo_daily_run_id" => daily_run&.id,
            "source_query" => best_analysis.keyword,
            "serp_result_count" => best_analysis.result_count,
            "daily_action_candidates_generated_count" => daily_run&.action_candidates_generated_count.to_i
          }
        )
      end
      candidates
    end

    private

    attr_reader :serp_run, :daily_run

    def integrated_candidates
      ActionCandidate.where(generation_source: "integrated_decision")
    end

    def top_business
      integrated_candidates.active_for_ranking.by_recommendation.first&.business ||
        serp_run&.serp_analyses&.successful&.includes(:business)&.first&.business
    end

    def duplicate_today?(business)
      business.action_candidates
              .where(generation_source: "integrated_decision", created_at: Time.zone.today.all_day)
              .exists?
    end

    def prompt_for(business, analysis)
      <<~PROMPT.squish
        #{business.name}について、SERP検索クエリ「#{analysis.keyword}」の市場観測結果とDaily RunのGA4/GSC/Revenue/Learningを統合して、最も期待値が高い改善案を1つ実装してください。SERP単独判断は禁止し、内部データと改善履歴を必ず確認してください。
      PROMPT
    end

    def message_for(business)
      return "SERP RunとDaily Runの統合判断対象はまだありません。" unless business

      "#{business.name}を最重要Businessとして、SERP市場観測と内部データを統合して判断します。"
    end
  end
end
