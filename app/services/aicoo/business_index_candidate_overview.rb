module Aicoo
  class BusinessIndexCandidateOverview
    Result = Data.define(:serp_business_ids, :new_business_pending_count)

    def self.call(businesses)
      business_ids = Array(businesses).filter_map(&:id)
      serp_scope = ActionCandidate
        .where(
          business_id: business_ids,
          generation_source: "serp",
          department: "new_business"
        )
        .select(:business_id)
        .distinct
      pending_scope = Aicoo::NewBusinessCandidateBoard.pending_scope
        .unscope(:includes)
        .select(:id)

      row = ActionCandidate.connection.select_one(
        <<~SQL.squish,
          SELECT
            COALESCE((
              SELECT string_agg(serp_candidates.business_id::text, ',')
              FROM (#{serp_scope.to_sql}) serp_candidates
            ), '') AS serp_business_ids,
            (
              SELECT COUNT(*)
              FROM (#{pending_scope.to_sql}) pending_candidates
            ) AS new_business_pending_count
        SQL
        "Business index candidate overview"
      )

      Result.new(
        serp_business_ids: row.fetch("serp_business_ids").split(",").filter_map { |id| Integer(id, exception: false) },
        new_business_pending_count: row.fetch("new_business_pending_count").to_i
      )
    end
  end
end
