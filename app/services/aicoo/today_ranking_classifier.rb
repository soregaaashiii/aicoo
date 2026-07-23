module Aicoo
  class TodayRankingClassifier
    ARTICLE_OPPORTUNITY_MODEL_NAME = "article_opportunity_analyzer_snapshot_v1".freeze
    INACTIVE_CATEGORIES = %w[unspecified fallback legacy].freeze
    MAIN_RANKING_CATEGORIES = %w[executable_improvement manual_action].freeze
    PREPARATION_READINESS = %w[needs_target needs_query needs_metric needs_completion_criteria needs_file_changes needs_before_after blocked needs_owner].freeze
    BLANK_TARGET_VALUES = [ "", "-", "未特定", "対象未特定", "未作成", "unspecified", "unknown" ].freeze
    ARTICLE_EXECUTABLE_TYPES = %w[
      ctr_improvement
      rank_improvement
      content_update
      internal_link_addition
      seo_improvement
      title_meta_update
      meta_update
      heading_update
      structure_update
      internal_link_update
    ].freeze
    ARTICLE_PREPARATION_TYPES = %w[
      shop_addition
      target_research
      data_preparation
      analytics_setup
      repository_setup
      execution_profile_setup
      measurement_setup
      new_article_planning
      article_planning
    ].freeze
    ARTICLE_MANUAL_TYPES = %w[
      shop_addition
      verified_shop_addition
      smoking_condition_confirmation
      shop_information_confirmation
      phone_confirmation
      publication_review
    ].freeze
    OWNER_MANUAL_EXECUTION_MODES = %w[manual manual_operation data_operation owner_decision].freeze
    OWNER_MANUAL_ACTION_TYPES = %w[
      shop_addition
      verified_shop_addition
      smoking_info_verify
      smoking_condition_confirmation
      shop_information_confirmation
      shop_phone_verify
      phone_confirmation
    ].freeze
    OWNER_ACTION_TASK_STATUSES = %w[draft waiting_approval approved failed].freeze

    Result = Data.define(
      :candidate_category,
      :business_id,
      :business_name,
      :target,
      :target_valid,
      :execution_brief_present,
      :evidence_complete,
      :raw_value_type,
      :raw_value,
      :actionability_multiplier,
      :category_multiplier,
      :included_in_main_ranking,
      :exclusion_reason,
      :article_opportunity_detected,
      :opportunity_type,
      :improvement_type,
      :human_required,
      :research_required,
      :approved,
      :repository_configured,
      :execution_profile_configured,
      :executable_rule_result,
      :manual_rule_result,
      :preparation_rule_result,
      :matched_classification_rule,
      :classification_reason
    )

    class << self
      def call(item)
        new(item).call
      end

      def business_for_candidate(candidate)
        metadata = candidate.metadata.to_h.deep_stringify_keys
        business_id = candidate.business_id ||
          metadata["business_id"].presence ||
          metadata.dig("execution_brief", "target", "business_id").presence ||
          metadata.dig("article_opportunity", "business_id").presence ||
          snapshot_business_id(metadata)

        candidate.business || Business.find_by(id: business_id)
      end

      def snapshot_business_id(metadata)
        snapshot_id = metadata["snapshot_id"]
        return if snapshot_id.blank?

        AicooDataSnapshot.where(id: snapshot_id).pick(:payload).to_h["business_id"].presence
      rescue StandardError
        nil
      end
    end

    def initialize(item)
      @item = item
      @record = item.respond_to?(:record) ? item.record : nil
      @candidate = @record.is_a?(ActionCandidate) ? @record : nil
      @metadata = @candidate&.metadata.to_h.deep_stringify_keys
    end

    def call
      category = candidate_category
      Result.new(
        candidate_category: category,
        business_id: resolved_business&.id || resolved_business_id,
        business_name: resolved_business&.name.presence || item_value(:business_name).to_s,
        target: target_value,
        target_valid: target_valid?,
        execution_brief_present: execution_brief_present?,
        evidence_complete: evidence_complete?,
        raw_value_type: raw_value_type,
        raw_value: raw_value,
        actionability_multiplier: actionability_multiplier(category),
        category_multiplier: category_multiplier(category),
        included_in_main_ranking: MAIN_RANKING_CATEGORIES.include?(category),
        exclusion_reason: exclusion_reason_for(category),
        article_opportunity_detected: article_opportunity?,
        opportunity_type: opportunity_type,
        improvement_type: improvement_type,
        human_required: human_required?,
        research_required: research_required?,
        approved: approved?,
        repository_configured: repository_configured?,
        execution_profile_configured: execution_profile_configured?,
        executable_rule_result: executable_rule_result,
        manual_rule_result: manual_rule_result,
        preparation_rule_result: preparation_rule_result,
        matched_classification_rule: matched_classification_rule(category),
        classification_reason: classification_reason(category)
      )
    end

    private

    attr_reader :item, :record, :candidate, :metadata

    def candidate_category
      return "legacy" if legacy?
      return "unspecified" if unspecified?
      return "fallback" if fallback?
      return "executable_improvement" if executable_improvement?
      return "manual_action" if manual_action?
      return "preparation" if preparation?

      candidate ? "unspecified" : non_candidate_category
    end

    def legacy?
      return false unless candidate
      return true if candidate.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)
      return true if metadata["ranking_cleanup_status"].to_s.in?(%w[resolved superseded rejected_duplicate rejected_irrelevant])
      return true if metadata["snapshot_status"].to_s.in?(%w[archived ignored])
      return true if metadata["archived_reason"].present?
      return true if metadata["legacy_article_analyzer_skipped"].present?
      return false if article_opportunity?

      candidate.generation_source.to_s == "business_analyzer" &&
        candidate.action_type.to_s.in?(%w[article_update article_create new_article_candidate seo_article]) &&
        metadata["article_id"].present? &&
        metadata["value_model_name"].blank?
    end

    def fallback?
      return false unless candidate

      metadata["today_fallback"] == true ||
        metadata["fallback_action"] == true ||
        metadata["fallback_reason"].present? ||
        candidate.generation_source.to_s.include?("fallback") ||
        candidate.title.to_s.include?("TODOを1件具体化")
    end

    def unspecified?
      return false unless candidate
      return true if resolved_business.blank? && resolved_business_id.blank?
      return false if article_opportunity? && target_valid?

      target_blank? && !new_article_candidate?
    end

    def preparation?
      return non_candidate_preparation? unless candidate
      return article_opportunity_preparation? if article_opportunity?

      return true if candidate.action_type.to_s == "data_preparation"
      return true if metadata["execution_readiness"].to_s.in?(PREPARATION_READINESS)

      false
    end

    def executable_improvement?
      return false unless candidate
      return article_opportunity_executable? if article_opportunity?
      return false unless target_valid?

      %w[article_update article_create new_article_candidate seo_article seo_improvement codex_revision lp_improvement].include?(candidate.action_type.to_s)
    end

    def article_opportunity_executable?
      resolved_business.present? &&
        target_valid? &&
        execution_brief_present? &&
        evidence_complete? &&
        !human_required? &&
        !research_required? &&
        ARTICLE_EXECUTABLE_TYPES.include?(improvement_type) &&
        metadata["production_candidate"] != false &&
        metadata["experimental_only"] != true
    end

    def manual_action?
      return non_candidate_manual? unless candidate
      return article_opportunity_manual? if article_opportunity?

      target_valid? && human_required?
    end

    def article_opportunity_manual?
      human_required? &&
        !research_required? &&
        target_valid? &&
        concrete_manual_target_present? &&
        ARTICLE_MANUAL_TYPES.include?(improvement_type)
    end

    def article_opportunity_preparation?
      return true if research_required?
      return true if ARTICLE_PREPARATION_TYPES.include?(improvement_type)
      return true if human_required? && !concrete_manual_target_present?
      return true if new_article_candidate? && target_value.to_s == "未作成"

      false
    end

    def article_opportunity?
      return false unless candidate

      return true if metadata["article_opportunity"].present?
      return true if metadata["value_model_name"].to_s == ARTICLE_OPPORTUNITY_MODEL_NAME &&
        metadata["analysis_source"].to_s == "article_analytics_snapshot" &&
        metadata["snapshot_id"].present? &&
        metadata["expected_improvement_score"].present?

      metadata["snapshot_id"].present? &&
        metadata["analysis_source"].to_s == "article_analytics_snapshot" &&
        metadata["expected_improvement_score"].present?
    end

    def new_article_candidate?
      candidate&.action_type.to_s.in?(%w[article_create new_article_candidate seo_article]) ||
        metadata["url_classification"].to_s == "proposed_new" ||
        metadata["target_url_type"].to_s == "proposed_new"
    end

    def target_valid?
      return false if metadata&.dig("url_classification").to_s.in?(%w[external_reference invalid])
      return false if metadata&.dig("target_url_type").to_s.in?(%w[external_reference invalid])
      return true if article_opportunity? && article_target.present?
      return true if new_article_candidate? && planned_target.present?

      !target_blank?
    end

    def target_blank?
      BLANK_TARGET_VALUES.include?(target_value.to_s.strip)
    end

    def target_value
      article_target.presence ||
        item_value(:target).presence ||
        metadata&.dig("target_url").presence ||
        metadata&.dig("target").presence ||
        metadata&.dig("action_plan", "target").presence
    end

    def article_target
      return unless article_opportunity?

      metadata["article_path"].presence ||
        metadata.dig("execution_brief", "target", "url").presence ||
        metadata.dig("execution_brief", "target", "path").presence ||
        metadata.dig("action_plan", "target").presence ||
        item_value(:target).presence
    end

    def planned_target
      item_value(:planned_url).presence ||
        metadata["planned_url"].presence ||
        metadata["proposed_url"].presence ||
        metadata["proposed_slug"].presence
    end

    def execution_brief_present?
      return true unless candidate

      metadata["execution_brief"].present? ||
        metadata["action_plan"].present? ||
        metadata["execution_steps"].present?
    end

    def evidence_complete?
      return true unless candidate
      return true if article_opportunity? && metadata["snapshot_id"].present? && raw_value.positive?

      metadata["evidence"].present? ||
        metadata["ranking_reason"].present? ||
        metadata["score_reasons"].present? ||
        item_value(:reason).present?
    end

    def improvement_type
      @improvement_type ||= begin
        raw = metadata&.dig("improvement_type").presence ||
          metadata&.dig("opportunity_type").presence ||
          metadata&.dig("execution_brief", "opportunity_type").presence ||
          metadata&.dig("execution_brief", "improvement_type").presence ||
          metadata&.dig("article_opportunity", "opportunity_type").presence ||
          metadata&.dig("article_opportunity", "improvement_type").presence ||
          opportunity_type

        raw.to_s
      end
    end

    def opportunity_type
      @opportunity_type ||= begin
        raw = metadata&.dig("opportunity_type").presence ||
          metadata&.dig("improvement_type").presence ||
          metadata&.dig("execution_brief", "opportunity_type").presence ||
          metadata&.dig("article_opportunity", "opportunity_type").presence

        raw.to_s
      end
    end

    def human_required?
      owner_action_item? ||
        (!article_opportunity? && OWNER_MANUAL_EXECUTION_MODES.include?(item_value(:execution_mode).to_s)) ||
        (!article_opportunity? && OWNER_MANUAL_EXECUTION_MODES.include?(candidate&.execution_mode.to_s)) ||
        OWNER_MANUAL_ACTION_TYPES.include?(candidate&.action_type.to_s) ||
        OWNER_MANUAL_ACTION_TYPES.include?(improvement_type) ||
        boolean_metadata?("human_required") ||
        boolean_metadata?("requires_human") ||
        boolean_metadata?("manual_required")
    end

    def research_required?
      boolean_metadata?("research_required") ||
        boolean_metadata?("target_research_required") ||
        boolean_metadata?("needs_research")
    end

    def approved?
      candidate&.approved_at.present? ||
        (record.is_a?(AutoRevisionTask) && record.approved_at.present?) ||
        metadata&.dig("approved") == true ||
        metadata&.dig("approval_status").to_s == "approved"
    end

    def repository_configured?
      !boolean_metadata?("repository_missing") &&
        !Array(metadata&.dig("codex_gate", "missing")).include?("repository") &&
        metadata&.dig("repository_configured") != false
    end

    def execution_profile_configured?
      !boolean_metadata?("execution_profile_missing") &&
        !Array(metadata&.dig("codex_gate", "missing")).include?("execution_profile") &&
        metadata&.dig("execution_profile_configured") != false
    end

    def concrete_manual_target_present?
      return true if metadata&.dig("target_record_id").present?
      return true if metadata&.dig("shop_id").present?
      return true if metadata&.dig("execution_brief", "target", "record_id").present?
      return true if Array(metadata&.dig("execution_brief", "target", "shops")).present?
      return true if Array(metadata&.dig("execution_brief", "target", "records")).present?

      target_valid?
    end

    def non_candidate_category
      return "manual_action" if non_candidate_manual?
      return "preparation" if non_candidate_preparation?

      "unspecified"
    end

    def non_candidate_manual?
      return true if owner_action_item?
      return false if item_value(:source_type).to_s == "auto_revision_task" && target_blank?

      target_valid? || item_value(:source_type).blank?
    end

    def non_candidate_preparation?
      return false if item_value(:source_type).to_s == "daily_run_issue"
      return false if owner_action_item?

      item_value(:source_type).to_s == "auto_revision_task" && target_blank?
    end

    def owner_action_item?
      item_value(:source_type).to_s == "auto_revision_task" &&
        record.is_a?(AutoRevisionTask) &&
        OWNER_ACTION_TASK_STATUSES.include?(record.status)
    end

    def executable_rule_result
      return "not_article_opportunity" unless article_opportunity?
      return "business_missing" if resolved_business.blank?
      return "target_invalid" unless target_valid?
      return "execution_brief_missing" unless execution_brief_present?
      return "evidence_missing" unless evidence_complete?
      return "human_required" if human_required?
      return "research_required" if research_required?
      return "unsupported_improvement_type:#{improvement_type}" unless ARTICLE_EXECUTABLE_TYPES.include?(improvement_type)
      return "not_production_candidate" if metadata["production_candidate"] == false || metadata["experimental_only"] == true

      "matched"
    end

    def manual_rule_result
      return "owner_action_waiting" if owner_action_item?
      return "daily_run_issue" if non_candidate_manual?
      return "not_article_opportunity" unless article_opportunity?
      return "human_not_required" unless human_required?
      return "target_invalid" unless target_valid?
      return "manual_target_missing" unless concrete_manual_target_present?
      return "unsupported_manual_type:#{improvement_type}" unless ARTICLE_MANUAL_TYPES.include?(improvement_type)

      "matched"
    end

    def preparation_rule_result
      return "non_candidate_target_missing" if non_candidate_preparation?
      return "not_article_opportunity" unless article_opportunity?
      return "research_required" if research_required?
      return "preparation_type:#{improvement_type}" if ARTICLE_PREPARATION_TYPES.include?(improvement_type)
      return "human_target_missing" if human_required? && !concrete_manual_target_present?
      return "new_article_planning" if new_article_candidate? && target_value.to_s == "未作成"

      "not_matched"
    end

    def matched_classification_rule(category)
      case category
      when "legacy"
        "legacy"
      when "fallback"
        "fallback"
      when "unspecified"
        "unspecified"
      when "executable_improvement"
        article_opportunity? ? "article_opportunity_executable" : "target_valid_executable"
      when "manual_action"
        article_opportunity? ? "article_opportunity_manual" : "manual_action"
      when "preparation"
        article_opportunity? ? "article_opportunity_preparation" : "preparation"
      else
        "unknown"
      end
    end

    def classification_reason(category)
      case category
      when "executable_improvement"
        article_opportunity? ? "ArticleOpportunityの#{improvement_type}で、Business・対象・根拠・実行Briefが揃っています" : "対象が特定済みの実行候補です"
      when "manual_action"
        if owner_action_item?
          "改修PipelineがOwnerの判断または手作業を待っています"
        else
          article_opportunity? ? "人手確認が必要で対象が特定済みです" : "人手で実行する具体的な候補です"
        end
      when "preparation"
        preparation_rule_result
      when "unspecified"
        "Businessまたは対象が未特定です"
      when "fallback"
        "fallback候補です"
      when "legacy"
        "旧候補または非アクティブ候補です"
      else
        "分類未確定"
      end
    end

    def raw_value_type
      "yen"
    end

    def raw_value
      if item.respond_to?(:action_expected_value_delta_yen)
        decimal(item.action_expected_value_delta_yen)
      elsif item.respond_to?(:expected_value_yen)
        decimal(item.expected_value_yen)
      else
        0.to_d
      end
    end

    def actionability_multiplier(category)
      return 1.0.to_d if category.in?(%w[executable_improvement manual_action])
      return 0.45.to_d if category == "preparation"
      return 0.1.to_d if category == "fallback"

      0.to_d
    end

    def category_multiplier(category)
      {
        "executable_improvement" => 1.0,
        "manual_action" => 0.85,
        "preparation" => 0.35,
        "fallback" => 0.2,
        "unspecified" => 0.0,
        "legacy" => 0.0
      }.fetch(category, 0.5).to_d
    end

    def exclusion_reason_for(category)
      return nil if MAIN_RANKING_CATEGORIES.include?(category)

      {
        "preparation" => "preparation_candidate",
        "unspecified" => "target_or_business_unspecified",
        "fallback" => "fallback_candidate",
        "legacy" => "legacy_candidate"
      }.fetch(category, "not_main_ranking")
    end

    def resolved_business
      @resolved_business ||= begin
        business = candidate&.business || (record.business if record.respond_to?(:business))
        business ||= Business.find_by(id: resolved_business_id) if resolved_business_id.present?
        business
      end
    end

    def resolved_business_id
      @resolved_business_id ||= begin
        candidate&.business_id ||
          (record.business_id if record.respond_to?(:business_id)) ||
          metadata&.dig("business_id").presence ||
          metadata&.dig("execution_brief", "target", "business_id").presence ||
          metadata&.dig("article_opportunity", "business_id").presence ||
          snapshot_business_id
      end
    end

    def snapshot_business_id
      self.class.snapshot_business_id(metadata)
    end

    def item_value(name)
      item.respond_to?(name) ? item.public_send(name) : nil
    end

    def decimal(value)
      value.to_s.delete(",").to_d
    end

    def boolean_metadata?(key)
      value = metadata&.dig(key)
      value == true || value.to_s == "true"
    end
  end
end
