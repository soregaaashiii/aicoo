require "uri"

module Aicoo
  class SerpEvidenceValidator
    Result = Data.define(
      :blocked,
      :reason,
      :business_domain,
      :serp_domains,
      :semantic_similarity,
      :metadata
    ) do
      def blocked?
        blocked == true
      end
    end

    class << self
      def call(...)
        new(...).call
      end

      def record_ignored!(validation, context: {})
        return unless validation&.blocked?

        payload = validation.metadata.merge(context.deep_stringify_keys).merge(
          "ignored_at" => Time.current.iso8601
        ).compact
        Rails.logger.info("[SerpEvidenceValidator] ignored_external_evidence #{payload.to_json}")

        run = AicooDailyRun.running.recent.first
        return unless run

        log_line = "[ignored_external_evidence] #{payload.to_json}"
        existing_log = run.run_log.to_s
        next_log = [ existing_log, log_line ].compact_blank.join("\n").last(12_000)
        run.update_columns(run_log: next_log, updated_at: Time.current)

        step = run.current_step
        return unless step

        step_metadata = step.metadata.to_h.deep_stringify_keys
        ignored = Array(step_metadata["ignored_external_evidence"]).first(19)
        step_metadata["ignored_external_evidence"] = [ payload ] + ignored
        step.update_columns(metadata: step_metadata, updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[SerpEvidenceValidator] failed to record ignored evidence: #{e.class}: #{e.message}")
      end
    end

    def initialize(business: nil, metadata: {}, title: nil, description: nil, execution_prompt: nil, evaluation_reason: nil, serp_analysis: nil)
      @business = business || serp_analysis&.business
      @metadata = metadata.to_h.deep_stringify_keys
      @title = title
      @description = description
      @execution_prompt = execution_prompt
      @evaluation_reason = evaluation_reason
      @serp_analysis = serp_analysis
    end

    def call
      if irrelevant_external_evidence?
        return Result.new(
          true,
          "ignored_external_evidence",
          business_domain,
          serp_domains,
          semantic_similarity,
          result_metadata("ignored_external_evidence")
        )
      end

      Result.new(false, nil, business_domain, serp_domains, semantic_similarity, result_metadata(nil))
    end

    private

    attr_reader :business, :metadata, :title, :description, :execution_prompt, :evaluation_reason, :serp_analysis

    def irrelevant_external_evidence?
      return false if external_urls.empty?
      return false unless unrelated_external_url?

      semantic_similarity.zero?
    end

    def unrelated_external_url?
      external_urls.any? { |url| url.match?(/it-trend\.jp|log_management/i) } ||
        evidence_text.match?(/ログ管理|操作ログ|監査ログ|ITトレンド|セキュリティ|ITシステム|log_management|it[-\s]?trend/i)
    end

    def semantic_similarity
      @semantic_similarity ||= begin
        return 0.0 if business && business_context.match?(/吸えログ|suelog|喫煙|飲食店|居酒屋|カフェ|バー/) &&
          evidence_text.match?(/ログ管理|操作ログ|監査ログ|ITトレンド|セキュリティ|ITシステム|log_management/i)

        shared = business_tokens & evidence_tokens
        return 0.0 if shared.empty?

        (shared.size.to_f / [ business_tokens.size, 1 ].max).round(2)
      end
    end

    def result_metadata(reason)
      {
        "blocked" => reason.present?,
        "validation_reason" => reason,
        "business_id" => business&.id,
        "business_name" => business&.name,
        "business_domain" => business_domain,
        "serp_domains" => serp_domains,
        "semantic_similarity" => semantic_similarity,
        "source_query" => metadata["source_query"].presence || metadata["query"].presence || serp_analysis&.keyword,
        "validator" => self.class.name
      }.compact
    end

    def business_domain
      @business_domain ||= begin
        url = business&.business_execution_profile&.production_url.presence ||
          business&.gsc_site_url.presence
        URI.parse(url.to_s).host.to_s.sub(/\Awww\./, "").presence
      rescue URI::InvalidURIError
        nil
      end
    end

    def serp_domains
      external_urls.filter_map do |url|
        URI.parse(url).host.to_s.sub(/\Awww\./, "").presence
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    def external_urls
      @external_urls ||= all_urls.reject { |url| owned_url?(url) }
    end

    def owned_url?(url)
      return false if business_domain.blank?

      URI.parse(url).host.to_s.sub(/\Awww\./, "") == business_domain
    rescue URI::InvalidURIError
      false
    end

    def all_urls
      @all_urls ||= begin
        from_metadata = metadata_urls(metadata)
        from_serp = serp_analysis ? serp_analysis.serp_results.limit(10).pluck(:url) : []
        from_text = evidence_text.scan(%r{https?://[^\s"'<>)\]]+})
        (from_metadata + from_serp + from_text).compact_blank.map { |url| url.to_s.delete_suffix("。").delete_suffix(",") }.uniq
      end
    end

    def metadata_urls(value)
      case value
      when Hash
        value.flat_map { |_key, child| metadata_urls(child) }
      when Array
        value.flat_map { |child| metadata_urls(child) }
      else
        text = value.to_s
        urls = text.scan(%r{https?://[^\s"'<>)\]]+})
        urls.presence || (text.start_with?("http://", "https://") ? [ text ] : [])
      end
    end

    def evidence_text
      @evidence_text ||= [
        title,
        description,
        execution_prompt,
        evaluation_reason,
        metadata,
        serp_analysis&.keyword,
        serp_analysis&.serp_results&.limit(10)&.map { |result| [ result.title, result.snippet, result.url ] }
      ].compact.join(" ")
    end

    def business_context
      @business_context ||= [
        business&.name,
        business&.business_type,
        business&.description,
        business&.business_execution_profile&.production_url,
        business&.gsc_site_url,
        business&.metadata
      ].compact.join(" ")
    end

    def business_tokens
      @business_tokens ||= tokenize(business_context)
    end

    def evidence_tokens
      @evidence_tokens ||= tokenize(evidence_text)
    end

    def tokenize(text)
      text.to_s.unicode_normalize(:nfkc).downcase.scan(/[a-z0-9]+|[一-龠ぁ-んァ-ヶー]{2,}/).uniq
    end
  end
end
