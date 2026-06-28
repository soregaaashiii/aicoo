module Aicoo
  module Serp
    class ScanRunner
      Result = Data.define(
        :started_at,
        :finished_at,
        :provider,
        :target_business_count,
        :query_count,
        :success_count,
        :failed_count,
        :result_count,
        :duration_seconds,
        :estimated_cost_yen,
        :limit,
        :scan_batch_id,
        :analyses
      )

      def self.queries_for_business(business, max_queries_per_business: 3)
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

        (configured_keywords.presence || fallback_keywords)
          .compact_blank
          .uniq
          .first(max_queries_per_business)
      end

      def initialize(provider: nil, location: "Japan", language: "ja", limit: nil, max_queries_per_business: 3)
        @provider = (provider.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
        @location = location.presence || "Japan"
        @language = language.presence || "ja"
        @limit = limit.to_i.positive? ? limit.to_i : Aicoo::Serp::ScanPlan.configured_limit
        @max_queries_per_business = max_queries_per_business.to_i.positive? ? max_queries_per_business.to_i : 3
        @scan_batch_id = SecureRandom.uuid
      end

      def call
        started_at = Time.current
        analyses = target_businesses.flat_map do |business|
          queries_for(business).map { |query| scan_query(business, query) }
        end
        finished_at = Time.current
        query_count = analyses.size
        result_count = analyses.sum { |analysis| analysis.result_count.to_i }
        estimated_cost_yen = estimated_cost_for(query_count)
        record_cost!(query_count:, estimated_cost_yen:)

        Result.new(
          started_at:,
          finished_at:,
          provider:,
          target_business_count: target_businesses.size,
          query_count:,
          success_count: analyses.count { |analysis| analysis.status == "success" },
          failed_count: analyses.count { |analysis| analysis.status == "failed" },
          result_count:,
          duration_seconds: (finished_at - started_at).round(2),
          estimated_cost_yen:,
          limit:,
          scan_batch_id:,
          analyses:
        )
      end

      private

      attr_reader :provider, :location, :language, :limit, :max_queries_per_business, :scan_batch_id

      def target_businesses
        @target_businesses ||= Business.real_businesses.where(status: "launched").includes(:business_data_source_settings).order(:name).to_a
      end

      def queries_for(business)
        self.class.queries_for_business(business, max_queries_per_business:)
      end

      def scan_query(business, query)
        started_at = Time.current
        analysis = business.serp_analyses.create!(
          keyword: query,
          search_engine: "google",
          location:,
          device: "desktop",
          provider:,
          status: "running",
          analyzed_at: Time.current,
          result_count: 0,
          raw_summary: {
            "source" => "ceo_mode_serp_scan",
            "provider" => provider,
            "query" => query,
            "limit" => limit,
            "scan_batch_id" => scan_batch_id,
            "scan_started_at" => started_at.iso8601
          }
        )

        result = Adapter.call(
          provider: provider.to_sym,
          type: :google_search,
          query:,
          location:,
          language:,
          limit:
        )
        save_success!(analysis, result)
      rescue StandardError => e
        save_failure!(analysis, e)
      end

      def save_success!(analysis, result)
        payload = result.to_h
        organic_results = payload.fetch("organic_results", [])
        organic_results.each do |row|
          analysis.serp_results.create!(
            position: row["position"],
            title: row["title"],
            url: row["url"],
            snippet: row["snippet"]
          )
        end
        analysis.update!(
          status: "success",
          result_count: organic_results.size,
          competition_score: competition_score(organic_results),
          summary: raw_summary_text(payload),
          error_message: nil,
          raw_summary: {
            "provider" => payload["provider"],
            "type" => payload["type"],
            "query" => payload["query"],
            "location" => payload["location"],
            "language" => payload["language"],
            "limit" => limit,
            "scan_batch_id" => scan_batch_id,
            "scan_started_at" => analysis.raw_summary["scan_started_at"],
            "scan_finished_at" => Time.current.iso8601,
            "fetched_at" => payload["fetched_at"],
            "result_count" => organic_results.size,
            "top_results" => organic_results.first(5).map { |row| row.slice("position", "title", "url", "snippet") },
            "people_also_ask_count" => payload.fetch("people_also_ask", []).size,
            "related_searches" => payload.fetch("related_searches", []).first(5)
          }
        )
        analysis
      end

      def save_failure!(analysis, error)
        if analysis
          analysis.update!(
            status: "failed",
            result_count: 0,
            competition_score: 0,
            summary: "SERP走査に失敗しました。",
            error_message: error.message,
            raw_summary: analysis.raw_summary.merge(
              "status" => "failed",
              "error_class" => error.class.name,
              "error_message" => error.message,
              "scan_finished_at" => Time.current.iso8601
            )
          )
          analysis
        else
          raise error
        end
      end

      def competition_score(results)
        [ results.size * 8, 100 ].min
      end

      def raw_summary_text(payload)
        top_titles = payload.fetch("organic_results", []).first(3).map { |row| row["title"] }.compact_blank
        [
          "provider=#{payload['provider']}",
          "results=#{payload.fetch('organic_results', []).size}",
          ("top=#{top_titles.join(' / ')}" if top_titles.any?)
        ].compact.join(" / ")
      end

      def estimated_cost_for(query_count)
        plan = Aicoo::Serp::ScanPlan.new.call(limit:)
        return 0 if plan.candidate_keyword_count.to_i.zero?

        (plan.estimated_cost_yen.to_d * (query_count.to_d / plan.candidate_keyword_count.to_d)).round.to_i
      end

      def record_cost!(query_count:, estimated_cost_yen:)
        profile = DataSourceCostProfile.for_source("serp")
        profile.update!(
          monthly_run_count: profile.monthly_run_count.to_i + query_count.to_i,
          monthly_spend_yen: profile.monthly_spend_yen.to_i + estimated_cost_yen.to_i,
          last_run_at: Time.current
        )
      end
    end
  end
end
