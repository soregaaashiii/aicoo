module Aicoo
  class ExploreSummary
    Result = Data.define(
      :source_counts,
      :observation_counts,
      :top_opportunities,
      :newest_observations,
      :new_observation_count,
      :converted_opportunity_count,
      :imported_today_count,
      :imported_this_week_count,
      :import_counts_by_source,
      :new_status_observation_count,
      :high_score_observation_count,
      :on_hold_observation_count,
      :pending_opportunity_count
    )

    def call
      Result.new(
        source_counts: source_counts,
        observation_counts: observation_counts,
        top_opportunities: ExploreObservation.unconverted.top_ranked.limit(5),
        newest_observations: ExploreObservation.recent.limit(5),
        new_observation_count: ExploreObservation.where(created_at: 7.days.ago..).count,
        converted_opportunity_count: ExploreObservation.where.not(opportunity_discovery_item_id: nil).count,
        imported_today_count: imported_today_count,
        imported_this_week_count: imported_this_week_count,
        import_counts_by_source: import_counts_by_source,
        new_status_observation_count: ExploreObservation.new_status.count,
        high_score_observation_count: ExploreObservation.new_status.high_score.count,
        on_hold_observation_count: ExploreObservation.where(status: "on_hold").count,
        pending_opportunity_count: OpportunityDiscoveryItem.where(status: "pending").count
      )
    end

    private

    def source_counts
      ExploreDataSource::SOURCE_TYPES.index_with do |source_type|
        ExploreDataSource.where(source_type:).count
      end
    end

    def observation_counts
      ExploreObservation::OBSERVATION_TYPES.index_with do |observation_type|
        ExploreObservation.where(observation_type:).count
      end
    end

    def imported_today_count
      ExploreImportLog.where(created_at: Time.current.all_day).sum(:imported_count)
    end

    def imported_this_week_count
      ExploreImportLog.where(created_at: Time.current.all_week).sum(:imported_count)
    end

    def import_counts_by_source
      imported_counts = ExploreImportLog.where(created_at: Time.current.all_day)
                                        .group(:source_type)
                                        .sum(:imported_count)
      ExploreDataSource::SOURCE_TYPES.index_with { |source_type| imported_counts.fetch(source_type, 0) }
    end
  end
end
