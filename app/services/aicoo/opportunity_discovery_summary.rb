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
    OwnerHomeResult = Data.define(:status_counts, :unconverted_opportunities)

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

    def call_for_owner_home
      OwnerHomeResult.new(
        status_counts:,
        unconverted_opportunities: OpportunityDiscoveryItem.where.not(status: "converted").top_ranked.limit(5).to_a
      )
    end

    private

    def status_counts
      counts = OpportunityDiscoveryItem.group(:status).count
      OpportunityDiscoveryItem::STATUSES.index_with { |status| counts.fetch(status, 0) }
    end

    def source_type_counts
      counts = OpportunityDiscoveryItem.group(:source_type).count
      OpportunityDiscoveryItem::SOURCE_TYPES.index_with { |source_type| counts.fetch(source_type, 0) }
    end
  end
end
