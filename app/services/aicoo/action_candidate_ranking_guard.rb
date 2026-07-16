module Aicoo
  class ActionCandidateRankingGuard
    IRRELEVANT_EXTERNAL_HOST_PATTERNS = [
      /it-trend\.jp/i
    ].freeze
    IRRELEVANT_EXTERNAL_TEXT_PATTERNS = [
      /log_management/i,
      /ログ管理/,
      /操作ログ/,
      /監査ログ/,
      /ITトレンド/,
      /it[-\s]?trend/i,
      /セキュリティ/,
      /ITシステム/
    ].freeze
    ARTICLE_ACTION_TYPES = %w[new_article_candidate article_create seo_article].freeze
    SEO_EXISTING_ACTION_TYPES = %w[seo_improvement article_update].freeze
    MEASUREMENT_ACTION_TYPES = %w[
      measurement_setup
      analytics_setup
      cta_tracking
      cta_measurement
      ga4_setup
      gsc_setup
      conversion_tracking
    ].freeze
    MEASUREMENT_TEXT_PATTERNS = [
      /CTA.*計測/,
      /計測設定/,
      /Google計測/,
      /GA4/,
      /GSC/,
      /イベント/,
      /generate_lead/,
      /CV.*計測/
    ].freeze

    class << self
      def rejection_reason(candidate)
        new(candidate).rejection_reason
      end

      def irrelevant_external_evidence?(candidate)
        new(candidate).irrelevant_external_evidence?
      end

      def measurement_action?(candidate)
        new(candidate).measurement_action?
      end

      def metric_path?(value)
        Aicoo::ActionTargetUrlResolver.metric_reference?(value.to_s)
      end
    end

    def initialize(candidate)
      @candidate = candidate
      @metadata = candidate.metadata.to_h.deep_stringify_keys
    end

    def rejection_reason
      return "irrelevant_external_evidence" if irrelevant_external_evidence?
      return "action_type_url_mismatch" if action_type_url_mismatch?
      return "metric_name_used_as_url" if metric_url_mismatch?

      nil
    end

    def irrelevant_external_evidence?
      external_irrelevant_urls.any? && irrelevant_text?
    end

    def measurement_action?
      candidate.action_type.to_s.in?(MEASUREMENT_ACTION_TYPES) ||
        MEASUREMENT_TEXT_PATTERNS.any? { |pattern| candidate_text.match?(pattern) }
    end

    private

    attr_reader :candidate, :metadata

    def action_type_url_mismatch?
      return false if article_action?

      planned_urls.any? { |url| article_path?(url) }
    end

    def metric_url_mismatch?
      target_values.any? { |value| self.class.metric_path?(value) }
    end

    def article_action?
      candidate.action_type.to_s.in?(ARTICLE_ACTION_TYPES) ||
        metadata["work_type"].to_s.in?(%w[new_article article_create])
    end

    def planned_urls
      [
        metadata["planned_url"],
        metadata["proposed_url"],
        metadata["recommended_url"],
        metadata["recommended_slug"],
        metadata.dig("article_candidate", "recommended_url")
      ].compact_blank.map(&:to_s)
    end

    def target_values
      [
        metadata["target_url"],
        metadata["target_url_or_identifier"],
        metadata["target_identifier"],
        metadata["page_path"],
        metadata.dig("action_plan", "target"),
        metadata.dig("action_plan", "target_url_or_identifier"),
        metadata.dig("action_expansion", "target"),
        metadata.dig("action_expansion", "target_url"),
        metadata.dig("evidence", "page_path")
      ].compact_blank.map(&:to_s)
    end

    def article_path?(value)
      value.to_s.start_with?("/articles/")
    end

    def external_irrelevant_urls
      all_urls.select do |url|
        IRRELEVANT_EXTERNAL_HOST_PATTERNS.any? { |pattern| url.match?(pattern) } ||
          IRRELEVANT_EXTERNAL_TEXT_PATTERNS.any? { |pattern| url.match?(pattern) }
      end
    end

    def all_urls
      text = [
        candidate.title,
        candidate.description,
        candidate.execution_prompt,
        candidate.evaluation_reason,
        metadata
      ].join(" ")
      text.scan(%r{https?://[^\s"'<>)\]]+}).map { |url| url.delete_suffix("。").delete_suffix(",") }.uniq
    end

    def irrelevant_text?
      IRRELEVANT_EXTERNAL_TEXT_PATTERNS.any? { |pattern| candidate_text.match?(pattern) } ||
        external_irrelevant_urls.any?
    end

    def candidate_text
      @candidate_text ||= [
        candidate.title,
        candidate.description,
        candidate.execution_prompt,
        candidate.evaluation_reason,
        metadata
      ].join(" ")
    end
  end
end
