module Aicoo
  module IdeaPipeline
    class IdeaScorer
      def initialize(item)
        @item = item
      end

      def call
        item.update!(
          market_score:,
          competition_score:,
          monetization_score:,
          automation_score:,
          serp_difficulty_score:,
          maintenance_cost_score:,
          expected_profit_yen:,
          final_score:,
          status: "scored",
          current_stage: "score",
          evaluated_at: Time.current,
          metadata: item.metadata.to_h.merge(
            "idea_score" => score_metadata,
            "score_generated_at" => Time.current.iso8601
          )
        )
        item
      end

      private

      attr_reader :item

      def text
        @text ||= [
          item.title,
          item.short_description,
          item.problem,
          item.target_user,
          item.revenue_model,
          item.mvp_concept,
          item.lp_concept
        ].join(" ")
      end

      def market_score
        @market_score ||= clamp(45 + keyword_bonus(%w[検索 比較 予約 地域 業務 AI テンプレート 診断]) + learning_bonus)
      end

      def competition_score
        @competition_score ||= clamp(55 - keyword_bonus(%w[ニッチ 地域 特化 テンプレート]) + keyword_bonus(%w[比較 予約 AI]) / 2)
      end

      def monetization_score
        @monetization_score ||= clamp(40 + keyword_bonus(%w[送客 問い合わせ 月額 SaaS 販売 アフィリエイト リード]))
      end

      def automation_score
        @automation_score ||= clamp(item.ai_implementation_score.presence || 50)
      end

      def serp_difficulty_score
        @serp_difficulty_score ||= clamp(100 - competition_score)
      end

      def maintenance_cost_score
        @maintenance_cost_score ||= clamp(100 - item.difficulty_score.to_d - item.development_hours.to_d)
      end

      def expected_profit_yen
        @expected_profit_yen ||= [
          (market_score * monetization_score * 45).round,
          20_000
        ].max
      end

      def final_score
        @final_score ||= clamp(
          market_score * 0.24 +
          monetization_score * 0.22 +
          automation_score * 0.16 +
          serp_difficulty_score * 0.14 +
          maintenance_cost_score * 0.10 +
          (100 - item.difficulty_score.to_d) * 0.08 +
          learning_bonus * 0.06
        ).round(2)
      end

      def keyword_bonus(words)
        words.count { |word| text.include?(word) } * 8
      end

      def learning_bonus
        @learning_bonus ||= begin
          positive = OwnerDecisionLog.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).where("created_at >= ?", 30.days.ago).count
          negative = OwnerDecisionLog.where(decision_type: %w[reject skip]).where("created_at >= ?", 30.days.ago).count
          clamp(10 + positive * 1.5 - negative, min: 0, max: 20)
        end
      end

      def score_metadata
        {
          "market_score" => market_score.to_f,
          "competition_score" => competition_score.to_f,
          "monetization_score" => monetization_score.to_f,
          "automation_score" => automation_score.to_f,
          "serp_difficulty_score" => serp_difficulty_score.to_f,
          "maintenance_cost_score" => maintenance_cost_score.to_f,
          "expected_profit_yen" => expected_profit_yen,
          "learning_bonus" => learning_bonus.to_f,
          "cost_optimization" => "SERPはfinal_score 60以上のIdeaのみ実行します。"
        }
      end

      def clamp(value, min: 0, max: 100)
        [ [ value.to_d, min.to_d ].max, max.to_d ].min
      end
    end
  end
end
