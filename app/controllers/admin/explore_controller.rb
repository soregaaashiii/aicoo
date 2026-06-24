module Admin
  class ExploreController < ApplicationController
    def index
      @explore_summary = Aicoo::ExploreSummary.new.call
      @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
      @focus_queue = Aicoo::ExploreObservationFocusQueue.new.call
      @data_sources = ExploreDataSource.includes(:explore_observations).order(:source_type, :name)
      @observations = ExploreObservation.includes(:explore_data_source, :opportunity_discovery_item).recent.limit(50)
      @import_logs = ExploreImportLog.recent.limit(10)
    end

    def focus
      @focus_queue = Aicoo::ExploreObservationFocusQueue.new.call
      @observation = @focus_queue.top_observation
    end

    def convert_to_opportunity
      observation = ExploreObservation.find(params.expect(:id))
      opportunity = observation.convert_to_opportunity!

      redirect_back fallback_location: admin_explore_observations_focus_path, notice: "Explore ObservationをOpportunityへ変換しました。"
    end

    def review_observation
      observation.mark_reviewed!

      redirect_to admin_explore_observations_focus_path, notice: "Explore Observationを確認済みにしました。"
    end

    def reject_observation
      observation.reject!

      redirect_to admin_explore_observations_focus_path, notice: "Explore Observationを却下しました。"
    end

    def hold_observation
      observation.hold!

      redirect_to admin_explore_observations_focus_path, notice: "Explore Observationを保留にしました。"
    end

    private

    def observation
      @observation ||= ExploreObservation.find(params.expect(:id))
    end
  end
end
