module Owner
  class LearningRecommendationsController < ApplicationController
    def create_action_candidate
      business = Business.real_businesses.find_by(id: recommendation_params[:business_id].presence) ||
                 Business.real_businesses.order(:name).first
      unless business
        redirect_to owner_learning_report_path, alert: "ActionCandidate化にはBusinessが必要です。"
        return
      end

      candidate = ActionCandidate.create!(
        business:,
        title: recommendation_params[:title],
        description: recommendation_params[:reason],
        evaluation_reason: recommendation_params[:recommended_action],
        action_type: "learning_improvement",
        generation_source: "learning_report",
        department: "lab",
        status: "idea",
        immediate_value_yen: 1_000,
        success_probability: 0.3,
        expected_hours: 1,
        confidence_score: 40,
        data_confidence_score: 40,
        execution_prompt: execution_prompt
      )

      redirect_to candidate, notice: "Learning Report RecommendationをActionCandidate化しました。"
    end

    def create_opportunity
      opportunity = OpportunityDiscoveryItem.create!(
        business: Business.real_businesses.find_by(id: recommendation_params[:business_id].presence),
        title: recommendation_params[:title],
        description: "#{recommendation_params[:reason]}\n\nRecommended Action:\n#{recommendation_params[:recommended_action]}",
        source_type: "learning_report",
        opportunity_score: opportunity_score,
        status: "new",
        metadata: {
          "recommendation_category" => recommendation_params[:category],
          "recommendation_priority" => recommendation_params[:priority]
        }
      )

      redirect_to owner_opportunity_path(opportunity), notice: "Learning Report RecommendationからOpportunityを作成しました。"
    end

    private

    def recommendation_params
      params.permit(:title, :reason, :recommended_action, :category, :priority, :business_id)
    end

    def execution_prompt
      <<~TEXT
        Learning Report Recommendationを実行してください。

        Category:
        #{recommendation_params[:category]}

        Reason:
        #{recommendation_params[:reason]}

        Recommended Action:
        #{recommendation_params[:recommended_action]}

        完了条件:
        - 予測精度改善につながるActionResult、Calibration、またはActionCandidate改善が行われている
        - 実行後にActionExecutionとActionResultへ記録できる
      TEXT
    end

    def opportunity_score
      case recommendation_params[:priority]
      when "critical" then 90
      when "high" then 75
      when "medium" then 60
      else 50
      end
    end
  end
end
