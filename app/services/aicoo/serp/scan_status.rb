module Aicoo
  module Serp
    class ScanStatus
      Result = Data.define(
        :provider,
        :api_key_configured,
        :last_scanned_at,
        :target_business_count,
        :candidate_keyword_count,
        :execution_status,
        :latest_analysis
      )

      def call
        Result.new(
          provider: current_provider,
          api_key_configured: api_key_configured?,
          last_scanned_at: latest_analysis&.analyzed_at,
          target_business_count: target_businesses.size,
          candidate_keyword_count: target_businesses.sum { |business| queries_for(business).size },
          execution_status: execution_status,
          latest_analysis:
        )
      end

      private

      def current_provider
        ENV["AICOO_SERP_PROVIDER"].presence || "serper"
      end

      def api_key_configured?
        ENV["SERPER_API_KEY"].present? || DataSourceCostProfile.find_by(source_key: "serp")&.api_key.present?
      end

      def target_businesses
        @target_businesses ||= Business.real_businesses.where(status: "launched").includes(:business_data_source_settings).order(:name).to_a
      end

      def latest_analysis
        @latest_analysis ||= SerpAnalysis.joins(:business)
                                         .merge(Business.real_businesses)
                                         .order(analyzed_at: :desc, created_at: :desc)
                                         .first
      end

      def execution_status
        return "SERP走査中" if SerpAnalysis.running.joins(:business).merge(Business.real_businesses).exists?
        return "SERP走査に失敗しました" if latest_analysis&.status == "failed"
        return "SERP走査が完了しました" if latest_analysis&.status == "success"

        "未実行"
      end

      def queries_for(business)
        configured_keywords = business.business_data_source_settings
                                      .find { |setting| setting.source_key == "serp" }
                                      &.connection_field_value("keyword")
                                      .to_s
                                      .split(/[\n,、]/)
                                      .map(&:strip)
                                      .compact_blank
        fallback_keywords = [
          business.name,
          [ business.name, business.description.to_s.split(/[。.\n]/).first ].compact_blank.join(" "),
          [ business.name, "比較" ].join(" ")
        ]
        (configured_keywords.presence || fallback_keywords).compact_blank.uniq.first(3)
      end
    end
  end
end
