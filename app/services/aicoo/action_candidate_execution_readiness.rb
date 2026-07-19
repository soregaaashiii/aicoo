module Aicoo
  class ActionCandidateExecutionReadiness
    READY = "ready"
    BLOCKED = "blocked"
    NEEDS_TARGET = "needs_target"
    NEEDS_QUERY = "needs_query"
    NEEDS_METRIC = "needs_metric"
    NEEDS_OWNER = "needs_owner"

    Result = Data.define(:readiness, :codex_eligible, :auto_revision, :auto_merge, :auto_deploy, :missing_items, :warnings, :metadata) do
      def ready?
        readiness == READY
      end
    end

    def self.call(action_candidate)
      new(action_candidate).call
    end

    def initialize(action_candidate)
      @action_candidate = action_candidate
      @metadata = action_candidate.metadata.to_h.deep_stringify_keys
      @missing_items = []
      @warnings = []
    end

    def call
      readiness = determine_readiness
      ready = readiness == READY
      Result.new(
        readiness:,
        codex_eligible: ready,
        auto_revision: ready,
        auto_merge: ready && truthy_metadata?("auto_merge"),
        auto_deploy: ready && truthy_metadata?("auto_deploy"),
        missing_items: missing_items.uniq,
        warnings: warnings.uniq,
        metadata: result_metadata(readiness, ready)
      )
    end

    private

    attr_reader :action_candidate, :metadata, :missing_items, :warnings

    def determine_readiness
      if Aicoo::ArticleOpportunityCodexGate.article_opportunity_candidate?(action_candidate)
        return article_opportunity_readiness
      end

      if action_candidate.action_type.to_s == "data_preparation"
        missing_items << "execution_phase_2_target"
        return NEEDS_TARGET
      end

      unless action_candidate.code_revision_execution_mode?
        warnings << "code_revision以外の実行方式です"
        return BLOCKED
      end

      return NEEDS_OWNER unless action_candidate.business
      return NEEDS_TARGET unless target_ready?
      query_metric_readiness = query_or_metric_readiness
      return query_metric_readiness unless query_metric_readiness == READY
      return BLOCKED unless execution_detail_ready?
      return BLOCKED if practicality_warning?

      READY
    end

    def article_opportunity_readiness
      gate = Aicoo::ArticleOpportunityCodexGate.call(action_candidate, require_approval: false, ignore_existing_task: true)
      return READY if gate.eligible?

      missing_items.concat(gate.reasons)
      return NEEDS_TARGET if gate.reasons.any? { |reason| reason.to_s.match?(/target|snapshot|internal_link/) }
      return NEEDS_QUERY if gate.reasons.include?("missing_information_present")
      return NEEDS_OWNER if gate.reasons.any? { |reason| reason.to_s.match?(/human|required|approval|profile|repository/) }

      BLOCKED
    end

    def target_ready?
      return true if target_record_id.present?
      return true if owned_existing_target_url.present?

      missing_items << "target_url_or_target_record_id"
      false
    end

    def query_or_metric_readiness
      return READY if target_query.present?
      return READY if target_metric.present?

      missing_items << (metric_action? ? "target_metric" : "target_query")
      metric_action? ? NEEDS_METRIC : NEEDS_QUERY
    end

    def execution_detail_ready?
      ok = true
      unless change_content.present?
        missing_items << "change_content"
        ok = false
      end
      unless completion_criteria.any?
        missing_items << "completion_criteria"
        ok = false
      end
      unless file_changes.any?
        missing_items << "file_changes"
        ok = false
      end
      unless before_after_ready?
        missing_items << "before_after"
        ok = false
      end
      unless action_candidate.execution_prompt.present?
        missing_items << "execution_prompt"
        ok = false
      end
      ok
    end

    def practicality_warning?
      warning = action_candidate.practicality_warning? || metadata["practicality_warning"] == true
      warnings << "実行可能性に警告があります" if warning
      warning
    end

    def owned_existing_target_url
      return @owned_existing_target_url if defined?(@owned_existing_target_url)

      raw = first_present(
        metadata["target_url"],
        metadata["owned_target_url"],
        metadata["page_path"],
        metadata.dig("action_plan", "target_url")
      )
      @owned_existing_target_url = nil
      return @owned_existing_target_url if raw.blank?
      return @owned_existing_target_url if Aicoo::ActionTargetUrlResolver.metric_reference?(raw.to_s)

      resolved = Aicoo::ActionTargetUrlResolver.call(raw, require_known_route: true)
      return @owned_existing_target_url if resolved.blank?

      policy = Aicoo::BusinessOwnedUrlPolicy.call(business: action_candidate.business, url: resolved)
      @owned_existing_target_url = policy.target_url_type == "owner_page" ? policy.url : nil
    end

    def target_record_id
      first_present(
        metadata["target_record_id"],
        metadata["article_id"],
        metadata["shop_id"],
        metadata.dig("target", "record_id")
      )
    end

    def target_query
      first_present(
        metadata["target_query"],
        metadata["source_query"],
        metadata["query"],
        metadata["search_query"],
        metadata["target_keyword"],
        metadata.dig("article_candidate", "search_query"),
        metadata.dig("execution_instruction", "search_query")
      )
    end

    def target_metric
      first_present(
        metadata["target_metric"],
        Array(metadata["target_metrics"]).first,
        metadata.dig("supporting_metrics", "metric_name"),
        metadata.dig("execution_instruction", "target_metric")
      )
    end

    def metric_action?
      text = [ action_candidate.title, action_candidate.action_type, metadata["concrete_task"] ].compact.join(" ")
      text.match?(/CTA|CV|計測|map|phone|affiliate|click|クリック|event|イベント/i)
    end

    def change_content
      first_present(
        metadata["change_content"],
        metadata["concrete_task"],
        metadata["recommended_action"],
        metadata.dig("action_plan", "summary"),
        metadata.dig("action_plan", "owner_output"),
        metadata.dig("execution_instruction", "page_change_type")
      )
    end

    def completion_criteria
      Array(
        metadata["completion_criteria"].presence ||
          metadata.dig("action_expansion", "completion_criteria").presence ||
          metadata.dig("execution_instruction", "completion_criteria")
      ).compact_blank
    end

    def file_changes
      Array(
        metadata["file_changes"].presence ||
          metadata["target_files"].presence ||
          metadata["changed_files"].presence ||
          metadata.dig("execution_instruction", "file_changes")
      ).compact_blank
    end

    def before_after_ready?
      return true if Array(metadata["before_after"]).any?
      return true if Array(metadata["before_after_items"]).any?
      return true if metadata.dig("execution_instruction", "quality", "has_before_after") == true

      before_values = [
        metadata["before"],
        metadata["current_title"],
        metadata["current_meta_description"],
        metadata.dig("action_plan", "before")
      ].compact_blank
      after_values = [
        metadata["after"],
        metadata["proposed_title"],
        metadata["proposed_meta_description"],
        metadata.dig("action_plan", "after")
      ].compact_blank
      before_values.any? && after_values.any?
    end

    def result_metadata(readiness, ready)
      {
        "execution_readiness" => readiness,
        "codex_eligible" => ready,
        "auto_revision" => ready,
        "auto_merge" => ready && truthy_metadata?("auto_merge"),
        "auto_deploy" => ready && truthy_metadata?("auto_deploy"),
        "execution_readiness_checked_at" => Time.current.iso8601,
        "execution_readiness_missing_items" => missing_items.uniq,
        "execution_readiness_warnings" => warnings.uniq
      }
    end

    def truthy_metadata?(key)
      metadata[key] == true || metadata[key].to_s == "true"
    end

    def first_present(*values)
      values.flatten.compact_blank.first
    end
  end
end
