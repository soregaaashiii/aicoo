module Aicoo
  class ActionCandidateTargetSanitizer
    URL_KEYS = %w[target_url target_url_or_identifier target_identifier page_path].freeze

    class << self
      def call(business:, metadata:, action_type: nil)
        new(business:, metadata:, action_type:).call
      end
    end

    def initialize(business:, metadata:, action_type: nil)
      @business = business
      @metadata = metadata.to_h.deep_dup.deep_stringify_keys
      @action_type = action_type.to_s
      @competitor_urls = Array(@metadata["competitor_urls"]) + Array(@metadata["external_reference_urls"])
    end

    def call
      collect_top_level_references
      collect_serp_competitors
      mark_irrelevant_external_evidence
      normalize_planned_url_for_new_content
      sanitize_top_level_targets
      sanitize_nested_targets
      mark_unresolved_target_when_competitor_reference
      normalize_measurement_targets
      apply_competitor_metadata
      metadata.compact
    end

    private

    attr_reader :business, :metadata, :action_type, :competitor_urls

    def normalize_planned_url_for_new_content
      return unless new_content_action?
      return if metadata["rejection_reason"].to_s == "irrelevant_external_evidence"

      URL_KEYS.each do |key|
        collect_reference_url(metadata[key]) if metadata[key].present?
      end
      planned = planned_owner_url
      metadata["planned_url"] = planned if planned.present?
      metadata["planned_url_type"] = "proposed_new" if planned.present?
      metadata["target_url"] = nil
      metadata["target_url_or_identifier"] = nil
      metadata["target_identifier"] = nil
      metadata["page_path"] = nil
      metadata["url_classification"] = "proposed_new" if planned.present?
      metadata["target_url_type"] = "proposed_new" if planned.present?
    end

    def collect_top_level_references
      URL_KEYS.each do |key|
        collect_reference_url(metadata[key]) if metadata[key].present?
      end
    end

    def sanitize_top_level_targets
      URL_KEYS.each do |key|
        next unless metadata[key].present?

        metadata[key] = sanitize_target_value(metadata[key])
      end
    end

    def sanitize_nested_targets
      sanitize_hash_target(metadata["action_plan"], "target")
      sanitize_hash_target(metadata["action_plan"], "target_url_or_identifier")
      sanitize_hash_target(metadata["action_expansion"], "target")
      sanitize_hash_target(metadata["action_expansion"], "target_url")
      sanitize_hash_array(metadata["action_expansion"], "target_pages")
      sanitize_hash_target(metadata["evidence"], "page_path")
      sanitize_hash_target(metadata.dig("decision", "selected"), "target_url_or_identifier")
      sanitize_hash_target(metadata.dig("opportunity", "target"), "identifier")
    end

    def sanitize_hash_target(hash, key)
      return unless hash.is_a?(Hash)
      return unless hash[key].present?

      if new_content_action? && url_like?(hash[key].to_s)
        result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: hash[key])
        competitor_urls << result.reference_url if result.reference_url.present?
        hash[key] = planned_owner_url
        return
      end

      hash[key] = sanitize_target_value(hash[key])
    end

    def sanitize_hash_array(hash, key)
      return unless hash.is_a?(Hash)

      hash[key] = Array(hash[key]).filter_map { |value| sanitize_target_value(value) }.uniq if hash[key].present?
    end

    def sanitize_target_value(value)
      raw = value.to_s.strip
      return value if raw.blank?
      return value if Aicoo::ActionTargetUrlResolver.metric_reference?(raw)
      return value unless url_like?(raw)
      return planned_target_value(raw, fallback: value) if new_content_action?

      result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: raw)
      if result.reference_url.present?
        competitor_urls << result.reference_url
        metadata["invalid_target_url_reason"] ||= "external_url_moved_to_competitor_urls"
        metadata["target_url_warning"] ||= "自社対象ページ未特定"
        metadata["target_url_type"] = "external_reference"
        metadata["url_classification"] = "external_reference"
        metadata["url_classification_reason"] ||= "domain_not_owned"
        metadata["resolved_own_domain"] ||= owner_domain
        metadata["url_verified_at"] ||= Time.current.iso8601
        return nil
      end
      if result.proposed_new?
        metadata["planned_url"] ||= result.url
        metadata["planned_url_type"] ||= "proposed_new"
        metadata["target_url_warning"] ||= "自社対象ページ未作成"
        metadata["target_url_type"] = "proposed_new"
        metadata["url_classification"] = "proposed_new"
        metadata["url_classification_reason"] ||= "own_url_not_existing"
        metadata["url_verified_at"] ||= Time.current.iso8601
        return nil
      end
      if result.invalid?
        metadata["invalid_target_url_reason"] ||= "invalid_target_url"
        metadata["target_url_warning"] ||= "対象URL要確認"
        metadata["target_url_type"] = "invalid"
        metadata["url_classification"] = "invalid"
        metadata["url_classification_reason"] ||= "invalid_or_unverified_url"
        metadata["url_verified_at"] ||= Time.current.iso8601
        return nil
      end

      metadata["target_url_type"] = "own_existing"
      metadata["url_classification"] = "own_existing"
      metadata["url_classification_reason"] ||= "owned_existing_url"
      metadata["resolved_own_domain"] ||= owner_domain
      metadata["url_verified_at"] ||= Time.current.iso8601
      result.url.presence || value
    end

    def collect_serp_competitors
      serp_rows.each do |row|
        url = row["url"].presence
        next if url.blank?

        result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url:)
        competitor_urls << result.reference_url if result.reference_url.present?
      end
    end

    def mark_irrelevant_external_evidence
      return unless irrelevant_external_evidence?

      metadata["target_url"] = nil
      metadata["target_url_or_identifier"] = nil
      metadata["target_identifier"] = nil
      metadata["page_path"] = nil
      metadata["planned_url"] = nil
      metadata["planned_url_type"] = nil
      metadata["url_classification"] = "external_reference"
      metadata["target_url_type"] = "external_reference"
      metadata["repair_reason"] ||= "external_reference"
      metadata["rejection_reason"] = "irrelevant_external_evidence"
      metadata["ranking_cleanup_status"] = "rejected_irrelevant"
      metadata["ranking_cleanup_reason"] = "irrelevant_external_evidence"
      metadata["url_classification_reason"] ||= "irrelevant_external_evidence"
      metadata["url_verified_at"] ||= Time.current.iso8601
    end

    def irrelevant_external_evidence?
      urls = competitor_urls.compact_blank + all_metadata_urls
      return false unless urls.any? { |url| url.match?(/it-trend\.jp|log_management/i) }

      text = [ metadata, urls ].join(" ")
      text.match?(/log_management|ログ管理|操作ログ|監査ログ|ITトレンド|it[-\s]?trend|セキュリティ|ITシステム/i)
    end

    def all_metadata_urls
      metadata.to_s.scan(%r{https?://[^\s"'<>)\]]+}).uniq
    end

    def normalize_measurement_targets
      return unless measurement_action?
      return if metadata["rejection_reason"].to_s == "irrelevant_external_evidence"

      metrics = metric_targets
      metadata["target_metrics"] = (Array(metadata["target_metrics"]) + metrics).compact_blank.uniq if metrics.any?
      %w[planned_url proposed_url recommended_url recommended_slug].each do |key|
        metadata[key] = nil if metadata[key].to_s.start_with?("/articles/")
      end
      URL_KEYS.each do |key|
        metadata[key] = nil if Aicoo::ActionTargetUrlResolver.metric_reference?(metadata[key].to_s)
      end
      clear_metric_nested_target(metadata["action_plan"], "target")
      clear_metric_nested_target(metadata["action_plan"], "target_url_or_identifier")
      clear_metric_nested_target(metadata["action_expansion"], "target")
      clear_metric_nested_target(metadata["action_expansion"], "target_url")
      clear_metric_nested_target(metadata["evidence"], "page_path")
      metadata["url_classification"] = "business_or_measurement_target"
      metadata["target_url_type"] = "business_or_measurement_target"
      metadata["target_url_warning"] ||= "計測対象はURLではなくイベント/指標です"
    end

    def clear_metric_nested_target(hash, key)
      return unless hash.is_a?(Hash)
      return unless Aicoo::ActionTargetUrlResolver.metric_reference?(hash[key].to_s)

      hash[key] = nil
    end

    def measurement_action?
      action_type.to_s.in?(Aicoo::ActionCandidateRankingGuard::MEASUREMENT_ACTION_TYPES) ||
        [ metadata["concrete_task"], metadata.dig("action_plan", "summary"), metadata["recommended_action"] ].compact.join(" ").match?(/CTA.*計測|計測設定|Google計測|GA4|GSC|イベント|generate_lead|CV.*計測/)
    end

    def metric_targets
      target_values = URL_KEYS.filter_map { |key| metadata[key].presence } +
        [
          metadata.dig("action_plan", "target"),
          metadata.dig("action_plan", "target_url_or_identifier"),
          metadata.dig("action_expansion", "target"),
          metadata.dig("action_expansion", "target_url"),
          metadata.dig("evidence", "page_path")
        ].compact
      target_values.filter_map do |value|
        next unless Aicoo::ActionTargetUrlResolver.metric_reference?(value.to_s)

        value.to_s.delete_prefix("/").split("/").select { |segment| Aicoo::ActionTargetUrlResolver::METRIC_NAMES.include?(segment) }
      end.flatten
    end

    def serp_rows
      rows = []
      rows.concat(Array(metadata["serp_top_results"]))
      rows.concat(Array(metadata.dig("serp_reference", "top_results")))
      rows.concat(Array(metadata.dig("serp_comparison", "top_results")))
      rows.map { |row| row.to_h.deep_stringify_keys }
    end

    def apply_competitor_metadata
      urls = competitor_urls.compact_blank.uniq
      metadata["competitor_urls"] = urls if urls.any?
      metadata["external_reference_urls"] = urls if urls.any?
      metadata["reference_urls"] = urls if urls.any?
      metadata["competitor_features"] ||= competitor_features if urls.any?
      metadata["missing_features"] ||= missing_features if urls.any?
      metadata["improvement_reason"] ||= improvement_reason if urls.any?
    end

    def mark_unresolved_target_when_competitor_reference
      return if new_content_action?
      return if competitor_urls.compact_blank.empty?
      return unless metadata["invalid_target_url_reason"].present?

      metadata["target_url"] = nil if metadata["target_url"].blank? || external_url?(metadata["target_url"])
      metadata["target_url_type"] = "external_reference" if metadata["target_url"].blank?
      metadata["url_classification"] = "external_reference" if metadata["target_url"].blank?
      metadata["target_url_warning"] ||= "自社対象ページ未特定"
    end

    def competitor_features
      Array(metadata["serp_common_structure"]).presence ||
        Array(metadata["serp_common_words"]).presence ||
        Array(metadata["recommended_sections"]).presence ||
        [ "競合の構成を参考情報として確認" ]
    end

    def missing_features
      Array(metadata["missing_elements"]).presence ||
        Array(metadata["recommended_sections"]).presence ||
        [ "自社ページに取り入れる改善要素を選定" ]
    end

    def improvement_reason
      "競合URLは改善対象ではなく参考情報です。Business所有ページへ不足要素を取り入れます。"
    end

    def url_like?(value)
      value.start_with?("/") || value.match?(/\Ahttps?:\/\//i)
    end

    def new_content_action?
      action_type.in?(%w[new_article_candidate article_create seo_article]) ||
        metadata["work_type"].to_s.in?(%w[new_article new_lp new_category article_create]) ||
        metadata["creation_type"].to_s.in?(%w[new_article new_lp new_category article_create])
    end

    def planned_target_value(raw, fallback:)
      result = collect_reference_url(raw)
      metadata["invalid_target_url_reason"] ||= "external_url_moved_to_reference_urls" if result.reference_url.present?
      metadata["url_classification"] = result.reference_url.present? ? "external_reference" : result.url_classification
      metadata["url_verified_at"] ||= Time.current.iso8601
      planned_owner_url
    end

    def collect_reference_url(value)
      result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value.to_s)
      competitor_urls << result.reference_url if result.reference_url.present?
      result
    end

    def planned_owner_url
      @planned_owner_url ||= begin
        slug_url = recommended_url_from_slug(metadata["recommended_slug"].presence || metadata["recommended_url_slug"].presence)
        value = metadata["planned_url"].presence || metadata["recommended_url"].presence || slug_url
        if value.blank?
          nil
        else
          result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value)
          result.reference_url.present? || result.invalid? ? slug_url : (result.owner_page? || result.proposed_new? ? result.url : slug_url)
        end
      end
    end

    def recommended_url_from_slug(value)
      slug = value.to_s.strip
      return nil if slug.blank?
      return nil if slug.start_with?("http://", "https://")
      return slug if slug.start_with?("/")

      "/articles/#{slug}"
    end

    def external_url?(value)
      return false unless value.to_s.match?(/\Ahttps?:\/\//i)

      Aicoo::BusinessOwnedUrlPolicy.call(business:, url: value.to_s).external_reference?
    end

    def owner_domain
      @owner_domain ||= begin
        fallback = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: "/").fallback_url.to_s
        URI.parse(fallback).host
      rescue StandardError
        nil
      end
    end
  end
end
