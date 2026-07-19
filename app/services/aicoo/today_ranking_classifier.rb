module Aicoo
  class TodayRankingClassifier
    ARTICLE_OPPORTUNITY_MODEL_NAME = "article_opportunity_analyzer_snapshot_v1".freeze
    INACTIVE_CATEGORIES = %w[unspecified fallback legacy].freeze
    MAIN_RANKING_CATEGORIES = %w[executable_improvement manual_action].freeze
    PREPARATION_READINESS = %w[needs_target needs_query needs_metric needs_completion_criteria needs_file_changes needs_before_after blocked needs_owner].freeze
    BLANK_TARGET_VALUES = [ "", "-", "未特定", "対象未特定", "未作成", "unspecified", "unknown" ].freeze

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
      :exclusion_reason
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
        exclusion_reason: exclusion_reason_for(category)
      )
    end

    private

    attr_reader :item, :candidate, :metadata

    def candidate_category
      return "legacy" if legacy?
      return "fallback" if fallback?
      return "unspecified" if unspecified?
      return "preparation" if preparation?
      return "executable_improvement" if executable_improvement?

      "manual_action"
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
      return false unless candidate
      return true if candidate.action_type.to_s == "data_preparation"
      return true if item_value(:execution_mode).to_s.in?(PREPARATION_READINESS)
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
        metadata["production_candidate"] != false &&
        metadata["experimental_only"] != true
    end

    def article_opportunity?
      return false unless candidate

      metadata["value_model_name"].to_s == ARTICLE_OPPORTUNITY_MODEL_NAME &&
        metadata["analysis_source"].to_s == "article_analytics_snapshot" &&
        metadata["snapshot_id"].present? &&
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
        metadata.dig("action_plan", "target").presence
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

    def raw_value_type
      article_opportunity? ? "expected_improvement_score" : "yen"
    end

    def raw_value
      if article_opportunity?
        decimal(metadata["expected_improvement_score"])
      elsif item.respond_to?(:action_expected_value_delta_yen)
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
        business = candidate&.business
        business ||= Business.find_by(id: resolved_business_id) if resolved_business_id.present?
        business
      end
    end

    def resolved_business_id
      @resolved_business_id ||= begin
        candidate&.business_id ||
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
  end
end
