module Aicoo
  class ExploreObservationFocusQueue
    Result = Data.define(:top_observation, :observations, :total_count, :high_priority_count, :generated_at)

    def call
      observations = focus_scope.limit(20)

      Result.new(
        top_observation: observations.first,
        observations: observations,
        total_count: focus_scope.count,
        high_priority_count: focus_scope.high_score.count,
        generated_at: Time.current
      )
    end

    private

    def focus_scope
      ExploreObservation.includes(:explore_data_source)
                        .new_status
                        .top_ranked
    end
  end
end
