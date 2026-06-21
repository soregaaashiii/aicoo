module Admin
  class AicooJudgeController < ApplicationController
    def show
      @analysis = AicooJudge::PredictionAnalyzer.new.call
      @trend_points = AicooJudge::PredictionTrend.new.call
    end

    def action_predictions
      @businesses = Business.order(:name)
      @judge_result = AicooJudge::ActionResultJudge.new(action_prediction_filters).call
    end

    private

    def action_prediction_filters
      params.permit(:business_id, :generation_source, :action_type, :start_date, :end_date).to_h.symbolize_keys
    end
  end
end
