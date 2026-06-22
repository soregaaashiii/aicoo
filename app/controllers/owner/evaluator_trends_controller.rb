module Owner
  class EvaluatorTrendsController < ApplicationController
    def index
      @range_days = params[:range].to_i == 30 ? 30 : 7
      @snapshots_by_date = MetaEvaluationSnapshot.global
                                                 .where(recorded_on: (@range_days - 1).days.ago.to_date..Date.current)
                                                 .order(recorded_on: :desc, evaluator_type: :asc)
                                                 .group_by(&:recorded_on)
    end
  end
end
