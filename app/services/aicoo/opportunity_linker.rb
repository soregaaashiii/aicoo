module Aicoo
  class OpportunityLinker
    require "digest"

    SOURCE_TYPE_MAP = {
      "serp" => "serp",
      "business_analyzer" => "gsc",
      "suelog_db" => "gsc",
      "ai_business" => "gsc",
      "integrated_decision" => "gsc",
      "opportunity_discovery" => "owner_discovery",
      "learning_report" => "learning_report"
    }.freeze

    def self.call(action_candidate)
      new(action_candidate).call
    end

    def initialize(action_candidate)
      @action_candidate = action_candidate
      @metadata = action_candidate.metadata.to_h.deep_stringify_keys
    end

    def call
      return if action_candidate.destroyed?
      return if action_candidate.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)

      opportunity = find_or_initialize_opportunity
      opportunity.assign_attributes(opportunity_attributes(opportunity))
      opportunity.save!
      link_candidate!(opportunity)
      opportunity
    end

    private

    attr_reader :action_candidate, :metadata

    def find_or_initialize_opportunity
      scope = OpportunityDiscoveryItem.where(business_id: action_candidate.business_id, opportunity_type:)
      scope.find_by("metadata ->> 'opportunity_identity_key' = ?", opportunity_identity_key) ||
        scope.find_by("metadata ->> 'source_key' = ?", source_key) ||
        OpportunityDiscoveryItem.new(business: action_candidate.business)
    end

    def opportunity_attributes(opportunity)
      first_detected_at = opportunity.metadata.to_h["first_detected_at"].presence || action_candidate.created_at.iso8601
      {
        title: opportunity_title,
        description: problem_text,
        summary: problem_text,
        source_type: source_type,
        opportunity_type:,
        status: opportunity.status.presence || "pending",
        opportunity_score: [ action_candidate.priority_score.to_i, 50 ].max,
        expected_value_yen: opportunity_expected_value(opportunity),
        confidence: action_candidate.confidence_score.presence || action_candidate.data_confidence_score.presence || 50,
        discovered_at: opportunity.discovered_at || action_candidate.created_at,
        metadata: opportunity.metadata.to_h.deep_stringify_keys.merge(
          "opportunity_identity_key" => opportunity_identity_key,
          "source_key" => source_key,
          "source_record_type" => "ActionCandidate",
          "source_record_id" => action_candidate.id,
          "target_keyword" => target_keyword,
          "target_url" => target_url,
          "planned_url" => planned_url,
          "reference_urls" => reference_urls,
          "problem" => problem_text,
          "evidence" => evidence,
          "first_detected_at" => first_detected_at,
          "last_detected_at" => Time.current.iso8601,
          "progress_status" => progress_status_for(opportunity),
          "related_action_candidate_ids" => related_candidate_ids(opportunity)
        ).compact
      }
    end

    def link_candidate!(opportunity)
      related_ids = related_candidate_ids(opportunity)
      link_metadata = metadata.merge(
        "opportunity_id" => opportunity.id,
        "opportunity_key" => source_key,
        "opportunity_identity_key" => opportunity_identity_key,
        "opportunity" => metadata["opportunity"].to_h.merge(
          "id" => opportunity.id,
          "key" => source_key,
          "opportunity_type" => opportunity_type,
          "status" => opportunity_status_label(opportunity),
          "estimated_value_yen" => opportunity.expected_value_yen.to_i
        )
      )

      prerequisite_id = prerequisite_candidate_id(opportunity)
      if prerequisite_id
        link_metadata["blocked"] = true
        link_metadata["blocked_reason"] = "先行施策が未完了です"
        link_metadata["prerequisite_action_candidate_id"] = prerequisite_id
      elsif link_metadata["blocked_reason"] == "先行施策が未完了です"
        link_metadata = link_metadata.except("blocked", "blocked_reason", "prerequisite_action_candidate_id")
      end

      action_candidate.update_columns(metadata: link_metadata, updated_at: Time.current)
      opportunity.update_columns(
        action_candidate_id: opportunity.action_candidate_id || action_candidate.id,
        metadata: opportunity.metadata.to_h.merge("related_action_candidate_ids" => (related_ids | [ action_candidate.id ])),
        updated_at: Time.current
      )
    end

    def related_candidate_ids(opportunity)
      ids = Array(opportunity.metadata.to_h["related_action_candidate_ids"]).map(&:to_i)
      ids | ActionCandidate.where("metadata ->> 'opportunity_identity_key' = ?", opportunity_identity_key).pluck(:id)
    end

    def prerequisite_candidate_id(opportunity)
      return unless sequencing_required?

      related = ActionCandidate.where(id: related_candidate_ids(opportunity))
      related.where(action_type: "new_article_candidate").reject(&:executed?).first&.id
    end

    def sequencing_required?
      action_candidate.action_type.in?(%w[seo_improvement article_update]) &&
        planned_url.present? &&
        target_url.blank?
    end

    def progress_status_for(opportunity)
      ids = related_candidate_ids(opportunity)
      return "未対応" if ids.empty?

      related = ActionCandidate.where(id: ids)
      return "解決済み" if related.any? && related.all?(&:executed?)
      return "一部対応" if related.any?(&:executed?)

      "未対応"
    end

    def opportunity_status_label(opportunity)
      opportunity.metadata.to_h["progress_status"].presence || progress_status_for(opportunity)
    end

    def opportunity_expected_value(opportunity)
      [ opportunity.expected_value_yen.to_i, action_candidate.immediate_value_yen.to_i, action_candidate.expected_profit_yen.to_i ].max
    end

    def opportunity_identity_key
      @opportunity_identity_key ||= Digest::SHA256.hexdigest(
        [
          action_candidate.business_id || "new_business",
          opportunity_type,
          target_keyword,
          target_url.presence || planned_url,
          source_key,
          problem_kind
        ].map { |value| normalize(value) }.join("::")
      )
    end

    def source_key
      metadata["opportunity_key"].presence ||
        metadata.dig("opportunity", "key").presence ||
        metadata["issue_key"].presence ||
        metadata["metric_rule"].presence ||
        metadata["source_query"].presence ||
        metadata["target_keyword"].presence ||
        metadata["target_query"].presence ||
        action_candidate.title
    end

    def opportunity_type
      metadata["opportunity_type"].presence ||
        metadata.dig("opportunity", "opportunity_type").presence ||
        metadata["work_type"].presence ||
        action_candidate.action_type
    end

    def source_type
      sources = Array(metadata["data_sources_used"]).map(&:to_s)
      return "serp" if action_candidate.generation_source == "serp" || sources.include?("serp")
      return "ga4" if sources.include?("ga4")
      return "gsc" if sources.include?("gsc")

      SOURCE_TYPE_MAP.fetch(action_candidate.generation_source.to_s, "owner_discovery")
    end

    def opportunity_title
      metadata.dig("opportunity", "title").presence ||
        metadata["opportunity_title"].presence ||
        "#{target_keyword.presence || action_candidate.title}の改善機会"
    end

    def target_keyword
      metadata["target_keyword"].presence ||
        metadata["target_query"].presence ||
        metadata["source_query"].presence ||
        metadata["query"].presence ||
        metadata["search_query"].presence ||
        metadata.dig("evidence", "query").presence ||
        metadata.dig("article_candidate", "search_query").presence
    end

    def target_url
      metadata["target_url"].presence ||
        metadata["target_url_or_identifier"].presence ||
        metadata["target_identifier"].presence ||
        metadata.dig("evidence", "page_path").presence
    end

    def planned_url
      metadata["planned_url"].presence ||
        metadata["recommended_url"].presence ||
        metadata["recommended_slug"].presence ||
        metadata["recommended_url_slug"].presence ||
        metadata.dig("article_candidate", "recommended_url_slug").presence
    end

    def reference_urls
      Array(metadata["reference_urls"]) |
        Array(metadata["competitor_urls"]) |
        Array(metadata["external_reference_urls"])
    end

    def problem_text
      metadata["problem"].presence ||
        metadata["issue_why"].presence ||
        metadata.dig("opportunity", "reason").presence ||
        action_candidate.description.presence ||
        action_candidate.title
    end

    def problem_kind
      metadata["problem_kind"].presence || metadata["work_type"].presence || action_candidate.action_type
    end

    def evidence
      metadata["evidence"].presence ||
        metadata["analyzer_evidence"].presence ||
        metadata["supporting_metrics"].presence ||
        {}
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkc).downcase.gsub(%r{https?://www\.}, "https://").gsub(/[[:space:]　]+/, " ").strip
    end
  end
end
