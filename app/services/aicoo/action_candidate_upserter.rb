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
      target_keyword
      query
      search_query
      gsc
      gsc_metrics
      ga4
      ga4_metrics
      business_db
      business_db_metrics
      supporting_metrics
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
            opportunity_key_for(candidate, metadata),
            candidate.action_type,
            target_url_for(metadata),
            planned_url_for(metadata),
            target_keyword_for(metadata),
            work_content_for(candidate, metadata),
            execution_mode_for(metadata)
          ].map { |value| normalize(value) }.join("::")
        )
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(%r{https?://www\.}, "https://").gsub(/[[:space:]　]+/, " ").strip
      end

      def opportunity_key_for(candidate, metadata)
        metadata.dig("opportunity", "key").presence ||
          metadata["opportunity_key"].presence ||
          metadata["opportunity_type"].presence ||
          metadata["suelog_insight_key"].presence ||
          metadata["external_record_id"].presence ||
          metadata["issue_key"].presence ||
          metadata["metric_rule"].presence ||
          metadata["source_query"].presence ||
          metadata["target_query"].presence ||
          candidate.title
      end

      def target_url_for(metadata)
        metadata["target_url"].presence ||
          metadata["target_url_or_identifier"].presence ||
          metadata["target_identifier"].presence ||
          metadata.dig("evidence", "page_path").presence ||
          metadata.dig("action_plan", "target").presence
      end

      def planned_url_for(metadata)
        metadata["planned_url"].presence ||
          metadata["recommended_url"].presence ||
          metadata["recommended_slug"].presence ||
          metadata["recommended_url_slug"].presence ||
          metadata.dig("article_candidate", "recommended_url_slug").presence
      end

      def target_keyword_for(metadata)
        metadata["target_keyword"].presence ||
          metadata["target_query"].presence ||
          metadata["source_query"].presence ||
          metadata["query"].presence ||
          metadata["search_query"].presence ||
          metadata.dig("evidence", "query").presence ||
          metadata.dig("article_candidate", "search_query").presence
      end

      def work_content_for(candidate, metadata)
        metadata["concrete_task"].presence ||
          metadata["recommended_action"].presence ||
          metadata.dig("action_plan", "owner_output").presence ||
          metadata.dig("action_plan", "summary").presence ||
          candidate.title
      end

      def execution_mode_for(metadata)
        metadata["execution_mode"].presence ||
          metadata.dig("action_plan", "execution_mode").presence
      end
    end

    def initialize(business:, attributes:)
      @business = business
      @attributes = attributes.deep_dup
    end

    def call
      attributes[:business] ||= business
      return nil if business&.action_candidate_generation_blocked?

      attributes[:metadata] = sanitized_metadata(attributes[:metadata], attributes[:action_type])
      evidence_validation = validate_evidence
      if evidence_validation.blocked?
        Aicoo::SerpEvidenceValidator.record_ignored!(
          evidence_validation,
          context: {
            "source" => "action_candidate_upserter",
            "generation_source" => attributes[:generation_source],
            "action_type" => attributes[:action_type],
            "title" => attributes[:title]
          }
        )
        return nil
      end
      attributes[:metadata]["dedupe_key"] = dedupe_key_for_attributes
      apply_sanitized_status!

      candidate = if (existing = existing_candidate)
        update_existing!(existing)
      else
        ActionCandidate.create!(attributes)
      end
      Aicoo::OpportunityLinker.call(candidate)
      candidate.reload
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

    def validate_evidence
      Aicoo::SerpEvidenceValidator.call(
        business:,
        metadata: attributes[:metadata],
        title: attributes[:title],
        description: attributes[:description],
        execution_prompt: attributes[:execution_prompt],
        evaluation_reason: attributes[:evaluation_reason]
      )
    end

    def dedupe_key_for_attributes
      candidate = ActionCandidate.new(
        business:,
        title: attributes[:title],
        action_type: attributes[:action_type],
        department: attributes[:department],
        generation_source: attributes[:generation_source],
        metadata: attributes[:metadata]
      )
      self.class.dedupe_key_for(candidate)
    end

    def apply_sanitized_status!
      return unless attributes[:metadata]["rejection_reason"].to_s == "irrelevant_external_evidence"

      attributes[:status] = "rejected"
    end

    def existing_candidate
      by_key = ActionCandidate
        .where(business:)
        .active_for_ranking
        .where("metadata ->> 'dedupe_key' = ?", attributes[:metadata]["dedupe_key"])
        .first
      return by_key if by_key

      scope = ActionCandidate
        .where(business:)
        .active_for_ranking
        .where(action_type: attributes[:action_type])
      scope.find_each
        .find { |candidate| self.class.dedupe_key_for(candidate) == attributes[:metadata]["dedupe_key"] }
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
      merged_metadata["evidence_sources"] = (Array(metadata["evidence_sources"]) | Array(incoming["evidence_sources"]) | [ attributes[:generation_source], incoming["generation_source"] ]).compact_blank
      merged_metadata["source_candidate_ids"] = (Array(metadata["source_candidate_ids"]).map(&:to_i) | [ candidate.id ]).compact
      merged_metadata["source_expected_values"] = Array(metadata["source_expected_values"]) + [ attributes[:expected_profit_yen] || attributes[:immediate_value_yen] ].compact
      merged_metadata["grouped_opportunity_count"] = [ metadata["grouped_opportunity_count"].to_i, 1 ].max + 1
      existing_value = candidate.expected_profit_yen.to_i
      incoming_value = (attributes[:expected_profit_yen] || attributes[:immediate_value_yen]).to_i
      final_value = [ existing_value, incoming_value ].max
      merged_metadata["deduplication_method"] = "max_confidence_same_market_opportunity"
      merged_metadata["primary_candidate_id"] = candidate.id
      merged_metadata["duplicate_candidate_ids"] = (Array(merged_metadata["duplicate_candidate_ids"]).map(&:to_i) | [ candidate.id ]).compact
      merged_metadata["base_expected_value_yen"] = final_value
      merged_metadata["independent_increment_yen"] = 0
      merged_metadata["market_cap_yen"] = final_value
      merged_metadata["final_expected_value_yen"] = final_value

      candidate.update!(
        immediate_value_yen: final_value,
        expected_profit_yen: final_value,
        expected_hours: attributes[:expected_hours] || candidate.expected_hours,
        cost_yen: attributes[:cost_yen] || candidate.cost_yen,
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
