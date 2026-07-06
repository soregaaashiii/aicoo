module Aicoo
  class ActionCandidateTargetSanitizer
    URL_KEYS = %w[target_url target_url_or_identifier target_identifier page_path].freeze

    class << self
      def call(business:, metadata:)
        new(business:, metadata:).call
      end
    end

    def initialize(business:, metadata:)
      @business = business
      @metadata = metadata.to_h.deep_dup.deep_stringify_keys
      @competitor_urls = Array(@metadata["competitor_urls"]) + Array(@metadata["external_reference_urls"])
    end

    def call
      sanitize_top_level_targets
      sanitize_nested_targets
      collect_serp_competitors
      ensure_owner_target_when_competitor_reference
      apply_competitor_metadata
      metadata.compact
    end

    private

    attr_reader :business, :metadata, :competitor_urls

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

      result = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: raw)
      if result.reference_url.present?
        competitor_urls << result.reference_url
        metadata["invalid_target_url_reason"] ||= "external_url_moved_to_competitor_urls"
      end
      metadata["target_url_type"] = result.target_url_type
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
      metadata["competitor_features"] ||= competitor_features if urls.any?
      metadata["missing_features"] ||= missing_features if urls.any?
      metadata["improvement_reason"] ||= improvement_reason if urls.any?
    end

    def ensure_owner_target_when_competitor_reference
      return if competitor_urls.compact_blank.empty?
      return unless metadata["invalid_target_url_reason"].present?

      fallback = Aicoo::BusinessOwnedUrlPolicy.call(business:, url: nil).url
      return if fallback.blank?

      metadata["target_url"] = fallback if metadata["target_url"].blank?
      metadata["target_url_type"] = "owner_page"
      metadata["action_plan"] ||= {}
      metadata["action_plan"]["target"] = fallback if metadata["action_plan"].is_a?(Hash) && metadata["action_plan"]["target"].blank?
      metadata["evidence"] ||= {}
      metadata["evidence"]["page_path"] = fallback if metadata["evidence"].is_a?(Hash) && metadata["evidence"]["page_path"].blank?
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
  end
end
