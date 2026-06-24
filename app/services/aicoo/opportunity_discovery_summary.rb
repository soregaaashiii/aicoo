module Aicoo
  class OpportunityDiscoverySummary
    Funnel = Data.define(:opportunity_count, :candidate_count, :execution_count, :result_count)
    Result = Data.define(
      :status_counts,
      :source_type_counts,
      :top_opportunities,
      :new_opportunities,
      :unconverted_opportunities,
      :funnel
    )

    def call
      Result.new(
        status_counts: status_counts,
        source_type_counts: source_type_counts,
        top_opportunities: OpportunityDiscoveryItem.top_ranked.limit(5),
        new_opportunities: OpportunityDiscoveryItem.where(status: "new").recent.limit(5),
        unconverted_opportunities: OpportunityDiscoveryItem.where.not(status: "converted").top_ranked.limit(5),
        funnel: Funnel.new(
          opportunity_count: OpportunityDiscoveryItem.count,
          candidate_count: OpportunityDiscoveryItem.where.not(action_candidate_id: nil).count,
          execution_count: ActionExecution.joins(action_candidate: :opportunity_discovery_items).distinct.count,
          result_count: ActionResult.joins(action_candidate: :opportunity_discovery_items).distinct.count
        )
      )
    end

    private

    def status_counts
      OpportunityDiscoveryItem::STATUSES.index_with { |status| OpportunityDiscoveryItem.where(status:).count }
    end

    def source_type_counts
      OpportunityDiscoveryItem::SOURCE_TYPES.index_with { |source_type| OpportunityDiscoveryItem.where(source_type:).count }
    end
  end
end
