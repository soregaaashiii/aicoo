require "json"

module Aicoo
  class BusinessIndexCandidateLoader
    Candidate = Data.define(
      :id,
      :business_id,
      :action_type,
      :title,
      :expected_profit_yen,
      :expected_learning_value_yen,
      :cost_yen,
      :success_probability,
      :metadata
    )
    SELECT_COLUMNS = %i[
      id
      business_id
      action_type
      title
      expected_profit_yen
      expected_learning_value_yen
      cost_yen
      success_probability
    ].freeze

    METADATA_FIELDS = %w[
      raw_expected_value_yen
      opportunity_group
      opportunity_key
      query
      keyword
      source_query
      target_url
      target_url_or_identifier
      search_intent
      metric_rule
      serp_analysis_id
      gsc_opportunity_id
      url_classification
      target_url_type
      impressions
      current_ctr
      ctr
      benchmark_ctr
      target_ctr
      conversion_rate
      cv_rate
      profit_per_conversion
      profit_per_cv
      value_per_conversion
      target_period
      cannibalization_rate
      value_model
      opportunity
      article_candidate
      action_plan
    ].freeze
    EVIDENCE_FIELDS = %w[
      query
      issue_type
      impressions
      current_ctr
      benchmark_ctr
      conversion_rate
    ].freeze
    METADATA_RECORD_ALIAS = "business_index_candidate_metadata".freeze
    METADATA_RECORD_SQL = <<~SQL.squish.freeze
      CROSS JOIN LATERAL jsonb_to_record(COALESCE("action_candidates"."metadata", '{}'::jsonb))
      AS #{METADATA_RECORD_ALIAS}(#{METADATA_FIELDS.map { |field| "#{field} jsonb" }.join(", ")})
    SQL
    EVIDENCE_RECORD_ALIAS = "business_index_candidate_evidence".freeze
    EVIDENCE_RECORD_SQL = <<~SQL.squish.freeze
      CROSS JOIN LATERAL jsonb_to_record(COALESCE("action_candidates"."metadata" -> 'evidence', '{}'::jsonb))
      AS #{EVIDENCE_RECORD_ALIAS}(#{EVIDENCE_FIELDS.map { |field| "#{field} jsonb" }.join(", ")})
    SQL

    def self.call(businesses)
      business_ids = Array(businesses).filter_map(&:id)
      return {} if business_ids.empty?

      scope = ActionCandidate
        .where(business_id: business_ids)
        .where("status IS NULL OR status NOT IN (?)", ActionCandidate::INACTIVE_STATUSES)
        .joins(METADATA_RECORD_SQL)
        .joins(EVIDENCE_RECORD_SQL)
        .select(
          *SELECT_COLUMNS,
          *METADATA_FIELDS.map { |field| Arel.sql("#{METADATA_RECORD_ALIAS}.#{field} AS metadata_#{field}") },
          *EVIDENCE_FIELDS.map { |field| Arel.sql("#{EVIDENCE_RECORD_ALIAS}.#{field} AS evidence_#{field}") }
        )

      ActionCandidate.connection.select_all(scope.to_sql).map { |row| build_candidate(row) }.group_by(&:business_id)
    end

    def self.build_candidate(row)
      metadata = METADATA_FIELDS.to_h do |field|
        [ field, decode_json(row["metadata_#{field}"]) ]
      end.compact
      evidence = EVIDENCE_FIELDS.to_h do |field|
        [ field, decode_json(row["evidence_#{field}"]) ]
      end.compact
      metadata["evidence"] = evidence if evidence.any?

      attributes = row.slice(*SELECT_COLUMNS.map(&:to_s)).symbolize_keys
      Candidate.new(**attributes, metadata:)
    end
    private_class_method :build_candidate

    def self.decode_json(value)
      value.is_a?(String) ? JSON.parse(value) : value
    end
    private_class_method :decode_json
  end
end
