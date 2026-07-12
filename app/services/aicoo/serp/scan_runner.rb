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

      def self.queries_for_business(business, max_queries_per_business: 3, exploration_mode: "ai_auto", exploration_query: nil)
        if market_exploration_business?(business)
          return market_exploration_queries_for(
            business,
            exploration_mode:,
            exploration_query:
          ).first(max_queries_per_business)
        end

        serp_queries = business.serp_queries
                               .enabled
                               .by_priority
                               .limit(max_queries_per_business)
                               .pluck(:query)
        return serp_queries if serp_queries.present?

        active_keywords = business.business_serp_keywords
                                  .fetchable
                                  .limit(max_queries_per_business)
                                  .pluck(:keyword)
        return active_keywords if active_keywords.present?

        configured_keywords = business.business_data_source_settings
                                      .find { |setting| setting.source_key == "serp" }
                                      &.connection_field_value("keyword")
                                      .to_s
                                      .split(/[\n,、]/)
                                      .map(&:strip)
                                      .compact_blank
        fallback_keywords = market_exploration_queries_for(business)

        (configured_keywords.presence || fallback_keywords)
          .compact_blank
          .uniq
          .first(max_queries_per_business)
      end

      def self.market_exploration_queries_for(business, exploration_mode: "ai_auto", exploration_query: nil)
        explicit_seed = exploration_query.to_s.strip
        if explicit_seed.present?
          return [
            explicit_seed,
            "#{explicit_seed} 困る",
            "#{explicit_seed} 比較",
            "#{explicit_seed} 料金",
            "#{explicit_seed} 自動化"
          ].uniq
        end

        theme = [
          business.respond_to?(:category) ? business.category : nil,
          business.respond_to?(:business_type) ? business.business_type.presence&.humanize : nil
        ].compact_blank.first

        seed =
          case exploration_mode.to_s
          when "industry"
            theme.presence || "中小企業 業務"
          when "category"
            theme.presence || "店舗 管理"
          when "keyword"
            theme.presence || "個人事業主 業務"
          else
            "個人事業主 業務"
          end

        [
          "#{seed} 自動化",
          "#{seed} 代行",
          "#{seed} 料金 比較",
          "#{seed} 管理 テンプレート",
          "#{seed} 困る 面倒",
          "#{seed} おすすめ",
          "#{seed} できない"
        ]
      end

      def self.query_plans_for_business(business, max_queries_per_business: 3, force: false, exploration_mode: "ai_auto", exploration_query: nil)
        all_serp_queries = business.serp_queries.enabled.by_priority.to_a
        serp_queries = all_serp_queries.select do |serp_query|
          force || (serp_query.runnable_today? && !serp_query.recently_successful?)
        end.first(max_queries_per_business)
        return serp_queries.map { |serp_query| QueryPlan.new(serp_query.query, serp_query, serp_query.country, serp_query.language) } if serp_queries.present?
        return [] if all_serp_queries.present?

        queries_for_business(business, max_queries_per_business:, exploration_mode:, exploration_query:).map do |query|
          QueryPlan.new(query, nil, "jp", "ja")
        end
      end

      def self.market_exploration_business?(business)
        business.name == "AICOO Market Exploration"
      end

      def initialize(provider: nil, location: "Japan", language: "ja", limit: nil, max_queries_per_business: 3, target_businesses: nil, serp_run: nil, force: false, max_total_queries: nil, single_serp_query: nil, allowed_serp_query_ids: nil, exploration_mode: "ai_auto", exploration_query: nil)
        @provider = (provider.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
        @location = location.presence || "Japan"
        @language = language.presence || "ja"
        @limit = limit.to_i.positive? ? limit.to_i : Aicoo::Serp::ScanPlan.configured_limit
        @max_queries_per_business = max_queries_per_business.to_i.positive? ? max_queries_per_business.to_i : 3
        @target_businesses = target_businesses
        @serp_run = serp_run
        @force = force
        @max_total_queries = max_total_queries.present? && max_total_queries.to_i.positive? ? max_total_queries.to_i : nil
        @single_serp_query = single_serp_query
        @allowed_serp_query_ids = allowed_serp_query_ids
        @exploration_mode = exploration_mode.presence || "ai_auto"
        @exploration_query = exploration_query
        @scan_batch_id = SecureRandom.uuid
      end

      def call
        started_at = Time.current
        analyses = scan_plans.map { |business, query_plan| scan_query(business, query_plan) }
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

      attr_reader :provider, :location, :language, :limit, :max_queries_per_business, :scan_batch_id, :serp_run, :single_serp_query, :exploration_mode, :exploration_query

      def target_businesses
        return [ single_serp_query.business ] if single_serp_query

        @target_businesses ||= Business.real_businesses
                                      .where(status: "launched", serp_enabled: true)
                                      .includes(:business_data_source_settings, :business_serp_keywords, :serp_queries)
                                      .order(:name)
                                      .to_a
      end

      def queries_for(business)
        if market_exploration_business?(business)
          return self.class.market_exploration_queries_for(
            business,
            exploration_mode:,
            exploration_query:
          ).first(max_queries_per_business)
        end

        self.class.queries_for_business(business, max_queries_per_business:)
      end

      def query_plans_for(business)
        return [ QueryPlan.new(single_serp_query.query, single_serp_query, single_serp_query.country, single_serp_query.language) ] if single_serp_query
        return allowed_query_plans_for(business) if @allowed_serp_query_ids

        self.class.query_plans_for_business(
          business,
          max_queries_per_business:,
          force: @force,
          exploration_mode:,
          exploration_query:
        )
      end

      def market_exploration_business?(business)
        self.class.market_exploration_business?(business)
      end

      def allowed_query_plans_for(business)
        business.serp_queries.where(id: @allowed_serp_query_ids).by_priority.map do |serp_query|
          QueryPlan.new(serp_query.query, serp_query, serp_query.country, serp_query.language)
        end
      end

      def scan_plans
        pairs = target_businesses.flat_map do |business|
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
