module Aicoo
  class ActionCandidateUpserter
    require "digest"

    MERGEABLE_METADATA_KEYS = %w[
      serp_reference
      serp_top_results
      serp_comparison
      competitor_urls
      external_reference_urls
      reference_urls
      value_model
      evidence
      evaluation_reason
      source_query
      target_query
      data_sources_used
      raw_immediate_value_yen
    ].freeze

    class << self
      def call(business:, attributes:)
        new(business:, attributes:).call
      end

      def dedupe_key_for(candidate)
        metadata = candidate.metadata.to_h.deep_stringify_keys
        business_id = candidate.business_id || metadata["business_id"]
        return if business_id.blank?

        Digest::SHA256.hexdigest(
          [
            business_id,
            metadata.dig("opportunity", "key").presence || metadata["opportunity_key"].presence || metadata["opportunity_type"].presence || metadata["suelog_insight_key"].presence || metadata["external_record_id"].presence || metadata["source_query"].presence || metadata["target_query"].presence || candidate.title,
            candidate.action_type,
            metadata["target_url"].presence || metadata["target_url_or_identifier"].presence,
            metadata["planned_url"].presence || metadata["recommended_url"].presence,
            metadata["target_query"].presence || metadata["source_query"].presence || metadata.dig("evidence", "query"),
            metadata["concrete_task"].presence || metadata.dig("action_plan", "owner_output").presence || candidate.title
          ].map { |value| normalize(value) }.join("::")
        )
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(%r{https?://www\.}, "https://").gsub(/[[:space:]　]+/, " ").strip
      end
    end

    def initialize(business:, attributes:)
      @business = business
      @attributes = attributes.deep_dup
    end

    def call
      attributes[:business] ||= business
      attributes[:metadata] = sanitized_metadata(attributes[:metadata], attributes[:action_type])
      attributes[:metadata]["dedupe_key"] = dedupe_key_for_attributes

      if (existing = existing_candidate)
        update_existing!(existing)
      else
        ActionCandidate.create!(attributes)
      end
    end

    private

    attr_reader :business, :attributes

    def sanitized_metadata(metadata, action_type)
      Aicoo::ActionCandidateTargetSanitizer.call(
        business:,
        metadata: metadata.to_h,
        action_type:
      )
    end

    def dedupe_key_for_attributes
      candidate = ActionCandidate.new(
        business:,
        title: attributes[:title],
        action_type: attributes[:action_type],
        metadata: attributes[:metadata]
      )
      self.class.dedupe_key_for(candidate)
    end

    def existing_candidate
      ActionCandidate
        .where(business:)
        .active_for_ranking
        .where("metadata ->> 'dedupe_key' = ?", attributes[:metadata]["dedupe_key"])
        .first
    end

    def update_existing!(candidate)
      metadata = candidate.metadata.to_h.deep_stringify_keys
      incoming = attributes[:metadata].to_h.deep_stringify_keys
      merged_metadata = metadata.merge(incoming.slice(*MERGEABLE_METADATA_KEYS)).merge(
        "dedupe_key" => incoming["dedupe_key"],
        "dedupe_updated_at" => Time.current.iso8601,
        "dedupe_update_source" => attributes[:generation_source].presence || incoming["created_by"],
        "dedupe_merged_count" => metadata["dedupe_merged_count"].to_i + 1
      )

      candidate.update!(
        immediate_value_yen: attributes[:immediate_value_yen] || candidate.immediate_value_yen,
        success_probability: attributes[:success_probability] || candidate.success_probability,
        confidence_score: attributes[:confidence_score] || candidate.confidence_score,
        data_confidence_score: attributes[:data_confidence_score] || candidate.data_confidence_score,
        priority_score: attributes[:priority_score] || candidate.priority_score,
        evaluation_reason: attributes[:evaluation_reason].presence || candidate.evaluation_reason,
        metadata: merged_metadata
      )
      candidate
    end
  end
end
