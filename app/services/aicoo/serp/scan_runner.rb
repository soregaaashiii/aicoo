module Aicoo
  module Serp
    class ScanRunner
      QueryPlan = Data.define(:query, :serp_query, :country, :language)
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

      def self.queries_for_business(business, max_queries_per_business: 3, exploration_mode: "ai_auto", exploration_query: nil, exploration_region: nil)
        if market_exploration_business?(business)
          return market_exploration_queries_for(
            business,
            exploration_mode:,
            exploration_query:,
            exploration_region:
          ).first(max_queries_per_business)
        end

        []
      end

      def self.market_exploration_queries_for(_business, exploration_mode: "ai_auto", exploration_query: nil, exploration_region: nil)
        explicit_seed = exploration_query.to_s.strip
        region = exploration_region.to_s.strip
        region_suffix = region.present? ? " #{region}" : ""
        if explicit_seed.present?
          return [
            "#{explicit_seed}#{region_suffix}",
            "#{explicit_seed} 困る#{region_suffix}",
            "#{explicit_seed} 料金#{region_suffix}",
            "#{explicit_seed} 自動化#{region_suffix}",
            "#{explicit_seed} 代行#{region_suffix}"
          ].uniq
        end

        seeds =
          case exploration_mode.to_s
          when "industry"
            [ "中小企業 バックオフィス", "士業 顧客管理", "飲食店 予約管理", "建設業 見積管理" ]
          when "keyword"
            [ "個人事業主 請求", "副業 確定申告", "営業 リスト管理", "採用 面接調整" ]
          else
            [ "個人事業主 業務", "中小企業 業務", "店舗 管理", "フリーランス 請求", "法人 契約管理" ]
          end

        intents = [ "困る", "面倒", "代行", "料金", "自動化", "管理 テンプレート", "できない" ]
        seeds.flat_map do |seed|
          intents.map { |intent| "#{seed} #{intent}#{region_suffix}" }
        end.uniq
      end

      def self.query_plans_for_business(business, max_queries_per_business: 3, force: false, exploration_mode: "ai_auto", exploration_query: nil, exploration_region: nil)
        return [] unless market_exploration_business?(business)

        queries_for_business(
          business,
          max_queries_per_business:,
          exploration_mode:,
          exploration_query:,
          exploration_region:
        ).map do |query|
          QueryPlan.new(query, nil, "jp", "ja")
        end
      end

      def self.market_exploration_business?(business)
        business.name == "AICOO Market Exploration"
      end

      def initialize(provider: nil, location: "Japan", language: "ja", limit: nil, max_queries_per_business: 3, serp_run: nil, force: false, max_total_queries: nil, exploration_mode: "ai_auto", exploration_query: nil, exploration_region: nil)
        @provider = (provider.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
        @location = location.presence || "Japan"
        @language = language.presence || "ja"
        @limit = limit.to_i.positive? ? limit.to_i : Aicoo::Serp::ScanPlan.configured_limit
        @max_queries_per_business = max_queries_per_business.to_i.positive? ? max_queries_per_business.to_i : 3
        @serp_run = serp_run
        @force = force
        @max_total_queries = max_total_queries.present? && max_total_queries.to_i.positive? ? max_total_queries.to_i : nil
        @exploration_mode = exploration_mode.presence || "ai_auto"
        @exploration_query = exploration_query
        @exploration_region = exploration_region
        @scan_batch_id = SecureRandom.uuid
      end

      def call
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::ScanRunner#call", context: memory_context) do
          started_at = Time.current
          plans = scan_plans
          analyses = plans.map { |business, query_plan| scan_query(business, query_plan) }
          finished_at = Time.current
          query_count = analyses.size
          result_count = analyses.sum { |analysis| analysis.result_count.to_i }
          estimated_cost_yen = estimated_cost_for(query_count)
          record_cost!(query_count:, estimated_cost_yen:)

          Result.new(
            started_at:,
            finished_at:,
            provider:,
            target_business_count: exploration_businesses.size,
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
      end

      private

      attr_reader :provider, :location, :language, :limit, :max_queries_per_business, :scan_batch_id, :serp_run, :exploration_mode, :exploration_query, :exploration_region

      def memory_context(extra = {})
        {
          serp_run_id: serp_run&.id,
          provider:,
          limit:,
          max_queries_per_business:,
          scan_batch_id:,
          exploration_mode:,
          exploration_region:
        }.merge(extra).compact
      end

      def exploration_businesses
        @exploration_businesses ||= [ market_exploration_business ]
      end

      def queries_for(business)
        if market_exploration_business?(business)
          return self.class.market_exploration_queries_for(
            business,
            exploration_mode:,
            exploration_query:,
            exploration_region:
          ).first(max_queries_per_business)
        end

        self.class.queries_for_business(business, max_queries_per_business:)
      end

      def query_plans_for(business)
        self.class.query_plans_for_business(
          business,
          max_queries_per_business:,
          force: @force,
          exploration_mode:,
          exploration_query:,
          exploration_region:
        )
      end

      def market_exploration_business
        Business.find_or_create_by!(name: "AICOO Market Exploration") do |business|
          business.description = "SERP新規事業探索の保存用システムBusiness"
          business.status = "launched"
          business.lifecycle_stage = "idea"
          business.business_type = "exploration"
          business.category = "market_exploration" if business.respond_to?(:category=)
          business.source = "system"
          business.created_by_aicoo = true
          business.launched = false
          business.daily_run_enabled = false
          business.serp_enabled = true
          business.auto_revision_mode = "manual"
          business.auto_build_enabled = false
          business.auto_deploy_mode = "manual"
          business.resource_status = "archived"
        end
      end

      def market_exploration_business?(business)
        self.class.market_exploration_business?(business)
      end

      def scan_plans
        pairs = exploration_businesses.flat_map do |business|
          query_plans_for(business).map { |query_plan| [ business, query_plan ] }
        end
        return pairs unless @max_total_queries

        pairs.first(@max_total_queries)
      end

      def scan_query(business, query_plan)
        started_at = Time.current
        query_plan.serp_query&.record_run!
        analysis = business.serp_analyses.create!(
          serp_run:,
          keyword: query_plan.query,
          search_engine: "google",
          location: country_to_location(query_plan.country),
          device: "desktop",
          provider:,
          status: "running",
          analyzed_at: Time.current,
          result_count: 0,
          raw_summary: {
            "source" => "ceo_mode_serp_scan",
            "provider" => provider,
            "query" => query_plan.query,
            "serp_query_id" => query_plan.serp_query&.id,
            "serp_run_id" => serp_run&.id,
            "limit" => limit,
            "scan_batch_id" => scan_batch_id,
            "scan_started_at" => started_at.iso8601
          }
        )

        result = Adapter.call(
          provider: provider.to_sym,
          type: :google_search,
          query: query_plan.query,
          location: country_to_location(query_plan.country),
          language: query_plan.language.presence || language,
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
            "serp_query_id" => analysis.raw_summary["serp_query_id"],
            "serp_run_id" => analysis.raw_summary["serp_run_id"],
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
        update_keyword_status!(analysis, organic_results)
        update_serp_query_success!(analysis)
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
          update_keyword_status!(analysis, [])
          update_serp_query_failure!(analysis)
          analysis
        else
          raise error
        end
      end

      def update_keyword_status!(analysis, organic_results)
        normalized = BusinessSerpKeyword.normalize(analysis.keyword)
        keyword = analysis.business.business_serp_keywords.find_or_initialize_by(normalized_keyword: normalized)
        keyword.keyword = analysis.keyword
        keyword.source = keyword.source.presence || "imported"
        keyword.status = "active" if keyword.status.blank? || keyword.status == "pending"
        keyword.priority_score = keyword.priority_score.presence || 50
        previous_rank = keyword.latest_rank
        keyword.last_checked_at = Time.current
        keyword.check_count = keyword.check_count.to_i + 1
        keyword.latest_rank = organic_results.filter_map { |row| row["position"].presence }.map(&:to_i).min
        keyword.metadata_json = keyword.metadata_json.to_h.merge(
          "latest_serp_analysis_id" => analysis.id,
          "latest_serp_status" => analysis.status,
          "latest_result_count" => analysis.result_count.to_i,
          "latest_error_message" => analysis.error_message,
          "previous_latest_rank" => previous_rank
        )
        keyword.save!
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SERP] keyword status update failed analysis_id=#{analysis.id} errors=#{e.record.errors.full_messages.to_sentence}")
      end

      def update_serp_query_success!(analysis)
        serp_query = serp_query_for(analysis)
        return unless serp_query

        candidate_count = ActionCandidate
          .where(business: analysis.business, generation_source: "serp")
          .where("metadata ->> 'source_query' = ? OR metadata ->> 'serp_keyword' = ?", analysis.keyword, analysis.keyword)
          .count
        serp_query.record_success!(candidate_count:)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SERP] serp query success update failed analysis_id=#{analysis.id} errors=#{e.record.errors.full_messages.to_sentence}")
      end

      def update_serp_query_failure!(analysis)
        serp_query = serp_query_for(analysis)
        serp_query&.record_failure!
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SERP] serp query failure update failed analysis_id=#{analysis.id} errors=#{e.record.errors.full_messages.to_sentence}")
      end

      def serp_query_for(analysis)
        id = analysis.raw_summary.to_h["serp_query_id"]
        return SerpQuery.find_by(id:) if id.present?

        analysis.business.serp_queries.find_by(normalized_query: SerpQuery.normalize(analysis.keyword))
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

      def country_to_location(country)
        { "jp" => "Japan", "us" => "United States" }.fetch(country.to_s.downcase, location)
      end
    end
  end
end
