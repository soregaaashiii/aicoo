module Aicoo
  class OpportunityActionCandidateConverter
    def initialize(opportunity)
      @opportunity = opportunity
    end

    def call
      return opportunity.action_candidate if opportunity.action_candidate
      return unless business_ready?
      return unless practical_enough?

      candidate = Aicoo::ActionCandidateUpserter.call(
        business: opportunity.business,
        attributes: {
          title: candidate_title,
          description: opportunity.summary.presence || opportunity.description,
          action_type: action_type,
          generation_source: "opportunity_discovery",
          department: "lab",
          status: "idea",
          immediate_value_yen: opportunity.expected_value_yen.to_i,
          expected_profit_yen: expected_profit_yen,
          success_probability: success_probability,
          expected_hours: expected_hours,
          cost_yen: cost_yen,
          confidence_score: opportunity.confidence.to_i,
          data_confidence_score: opportunity.confidence.to_i,
          evaluation_reason: evaluation_reason,
          execution_prompt: execution_prompt,
          metadata: candidate_metadata
        }
      )
      opportunity.update!(action_candidate: candidate, status: "converted")
      candidate
    end

    private

    attr_reader :opportunity

    def business_ready?
      return true if opportunity.business

      opportunity.update_columns(
        practicality_warning: true,
        practicality_reason: "新規サービス候補のため、先にBusiness下書きを作成してください。",
        metadata: opportunity.metadata.to_h.merge(
          "new_service_candidate" => true,
          "business_creation_required" => true
        ),
        updated_at: Time.current
      )
      false
    end

    def practical_enough?
      score = opportunity.practicality_score || Aicoo::PracticalityScorer.new(opportunity).call.practicality_score
      if score.to_d < Aicoo::PracticalityScorer::MIN_CANDIDATE_SCORE
        opportunity.update_columns(
          practicality_score: score,
          practicality_warning: true,
          practicality_reason: "Practicalityが30未満のためActionCandidate化せずOpportunityに残しました。",
          updated_at: Time.current
        )
        return false
      end

      true
    end

    def candidate_title
      "Explore検証: #{opportunity.title}"
    end

    def action_type
      case opportunity.opportunity_type
      when "lp_test"
        "build_lp"
      when "serp_research"
        "serp_research"
      when "revenue_experiment"
        "seo_improvement"
      else
        "opportunity_validation"
      end
    end

    def expected_profit_yen
      (opportunity.expected_value_yen.to_i * success_probability).to_i
    end

    def success_probability
      [ [ opportunity.confidence.to_d / 100, 0.2.to_d ].max, 0.75.to_d ].min
    end

    def expected_hours
      opportunity.opportunity_type == "lp_test" ? 2 : 1
    end

    def cost_yen
      opportunity.opportunity_type == "lp_test" ? 5_000 : 0
    end

    def evaluation_reason
      "Explore Opportunityから生成。market=#{opportunity.market_signal_score.to_i}, urgency=#{opportunity.urgency_score.to_i}, monetization=#{opportunity.monetization_score.to_i}, feasibility=#{opportunity.feasibility_score.to_i}, competition=#{opportunity.competition_score.to_i}"
    end

    def execution_prompt
      <<~TEXT
        Explore Opportunityを小さく検証してください。

        目的:
        #{opportunity.title}

        背景:
        #{opportunity.summary.presence || opportunity.description.presence || "-"}

        実行内容:
        - 低コストで検証できる最小施策を1つ作る
        - 検索・LP・記事・導線のどれで検証するか決める
        - 実行後にActionResultへ結果を登録する

        完了条件:
        - 検証施策が公開または実行されている
        - 次に見るべき指標が決まっている
      TEXT
    end

    def candidate_metadata
      {
        "opportunity_id" => opportunity.id,
        "opportunity_source_type" => opportunity.source_type,
        "opportunity_type" => opportunity.opportunity_type,
        "source_observation_id" => opportunity.source_observation_id,
        "expected_value_yen" => opportunity.expected_value_yen,
        "confidence" => opportunity.confidence&.to_s
      }.merge(opportunity.metadata.to_h)
    end
  end
end
