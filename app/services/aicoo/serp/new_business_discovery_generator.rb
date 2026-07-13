require "digest"
require "uri"

module Aicoo
  module Serp
    class NewBusinessDiscoveryGenerator
      Result = Data.define(
        :candidates,
        :created_count,
        :duplicate_count,
        :blank_query_count,
        :no_result_count,
        :failed_count,
        :existing_improvement_count,
        :serp_analyses_checked,
        :serp_results_checked,
        :errors
      )

      MARKET_INTENT_PATTERN = /困る|面倒|代行|比較|料金|おすすめ|できない|自動化|管理|テンプレート|法人|個人事業主|AI|SaaS|ツール|アプリ|予約|確認|チェック|作成|生成/i
      QUERY_NAME_SUFFIX_PATTERN = /の検証事業|比較|料金|おすすめ|困る|面倒|できない|大阪|東京|日本|法人|個人事業主|代行|自動化|管理|テンプレート/i
      REGION_WORDS = %w[大阪 東京 日本 全国 京都 神戸 梅田 難波 名古屋 福岡 横浜 札幌 仙台].freeze
      INTENT_WORDS = %w[代行 困る 面倒 比較 料金 おすすめ できない 自動化 管理 テンプレート 法人 個人事業主 AI SaaS ツール アプリ 予約 確認 チェック 作成 生成].freeze
      CUSTOMER_KEYWORDS = {
        /飲食店|レストラン|居酒屋|カフェ|バー/ => "飲食店",
        /個人事業主|フリーランス/ => "個人事業主",
        /中小企業|法人|会社/ => "中小企業",
        /不動産|賃貸/ => "不動産会社",
        /美容室|サロン/ => "美容サロン",
        /クリニック|病院|歯科/ => "クリニック",
        /士業|税理士|行政書士|社労士/ => "士業事務所",
        /採用|求人/ => "採用担当者"
      }.freeze
      SERVICE_FOCUS_RULES = [
        [ /Googleマップ|MEO|マップ|口コミ|レビュー/, "Googleマップ運用" ],
        [ /SNS|Instagram|インスタ|X|TikTok|LINE|集客/, "SNS集客" ],
        [ /予約|電話|受付|問い合わせ/, "予約受付" ],
        [ /メニュー|チラシ|デザイン|制作/, "メニュー制作" ],
        [ /採用|求人|人材/, "採用支援" ],
        [ /請求|経理|会計|領収書|バックオフィス/, "請求管理" ],
        [ /在庫|発注|仕入/, "在庫管理" ],
        [ /FAQ|問い合わせ|カスタマーサポート/, "問い合わせ対応" ],
        [ /比較|選び方|おすすめ/, "比較ナビ" ],
        [ /困る|面倒|できない|トラブル|不満/, "業務改善" ]
      ].freeze

      def initialize(serp_run:, limit: 10, backfill: false)
        @serp_run = serp_run
        @limit = limit.to_i.positive? ? limit.to_i : 10
        @backfill = backfill
        @errors = []
        @duplicate_count = 0
        @blank_query_count = 0
        @no_result_count = 0
      end

      def call
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::NewBusinessDiscoveryGenerator#call", context: memory_context) do
          candidates = discoverable_analyses.filter_map { |analysis| create_candidate_for(analysis) }
          Result.new(
            candidates:,
            created_count: candidates.size,
            duplicate_count: duplicate_count,
            blank_query_count: blank_query_count,
            no_result_count: no_result_count,
            failed_count: errors.size,
            existing_improvement_count: existing_improvement_count,
            serp_analyses_checked: source_analyses.count,
            serp_results_checked: source_results_count,
            errors: errors.first(10)
          )
        end
      end

      private

      attr_reader :serp_run, :limit, :errors, :backfill
      attr_accessor :duplicate_count, :blank_query_count, :no_result_count

      def memory_context(extra = {})
        {
          serp_run_id: serp_run&.id,
          limit:,
          backfill:
        }.merge(extra).compact
      end

      def discoverable_analyses
        top = []
        source_analyses.find_each do |analysis|
          next unless market_discovery_analysis?(analysis)

          top << [ market_score(analysis), analysis ]
          top = top.sort_by { |score, _analysis| -score }.first(limit) if top.size > limit
        end
        top.sort_by { |score, _analysis| -score }.map { |_score, analysis| analysis }
      end

      def source_analyses
        serp_run.serp_analyses.includes(:business)
      end

      def source_results_count
        SerpResult.where(serp_analysis_id: serp_run.serp_analyses.select(:id)).count
      end

      def market_discovery_analysis?(analysis)
        return blank_query!(analysis) if analysis.keyword.blank?
        return no_result!(analysis) unless analysis.serp_results.exists?

        true
      end

      def blank_query!(_analysis)
        self.blank_query_count += 1
        false
      end

      def no_result!(_analysis)
        self.no_result_count += 1
        false
      end

      def create_candidate_for(analysis)
        if duplicate_candidate?(analysis)
          self.duplicate_count += 1
          return nil
        end

        candidate = ActionCandidate.create!(candidate_attributes(analysis))
        publish_candidate!(candidate)
        candidate.reload
        return candidate if manual_edit_required?(candidate)
        return candidate if candidate.business_id.present? && candidate.metadata.to_h.dig("auto_new_business_publication", "completed")

        mark_publication_failed!(candidate, "business_auto_publish_failed")
        nil
      rescue StandardError => e
        errors << {
          "serp_analysis_id" => analysis.id,
          "query" => analysis.keyword,
          "error_class" => e.class.name,
          "error_message" => e.message
        }
        nil
      end

      def mark_publication_failed!(candidate, reason)
        errors << {
          "action_candidate_id" => candidate.id,
          "error_class" => reason,
          "error_message" => "SERP新規事業候補をBusiness化できませんでした。"
        }
        candidate.update_columns(
          status: "archived",
          metadata: candidate.metadata.to_h.merge(
            "auto_new_business_publication" => {
              "completed" => false,
              "failed" => true,
              "reason" => reason,
              "failed_at" => Time.current.iso8601
            }
          ),
          updated_at: Time.current
        )
      end

      def publish_candidate!(candidate)
        return if candidate.metadata.to_h.dig("auto_new_business_publication", "completed")
        return unless auto_publishable?(candidate)

        Aicoo::Serp::AutoNewBusinessPublisher.call(
          serp_run:,
          candidates: [ candidate ],
          source: backfill ? "serp_backfill_discovery" : "serp_discovery"
        )
      end

      def manual_edit_required?(candidate)
        candidate.metadata.to_h.dig("business_idea_quality", "status") == "needs_edit"
      end

      def auto_publishable?(candidate)
        candidate.metadata.to_h.dig("business_idea_quality", "auto_publishable") == true
      end

      def candidate_attributes(analysis)
        idea = business_idea_for(analysis)
        quality = business_idea_quality_for(analysis, idea)
        {
          business: nil,
          title: idea.fetch("business_name"),
          description: business_idea_description(analysis, idea),
          action_type: "new_business",
          department: "new_business",
          generation_source: "serp",
          status: quality.auto_publishable ? "idea" : "planning",
          immediate_value_yen: expected_market_value_yen(analysis),
          success_probability: success_probability_for(analysis),
          expected_hours: 2.0,
          cost_yen: 0,
          confidence_score: confidence_for(analysis),
          data_confidence_score: confidence_for(analysis),
          priority_score: [ market_score(analysis), 95 ].min,
          execution_prompt: validation_plan_for(analysis, idea),
          evaluation_reason: "serp:new_business_discovery",
          metadata: candidate_metadata(analysis, idea, quality)
        }
      end

      def candidate_metadata(analysis, idea = business_idea_for(analysis), quality = business_idea_quality_for(analysis, idea))
        {
          "source" => "serp",
          "candidate_kind" => "new_business",
          "business_flow" => quality.auto_publishable ? "serp_auto_added" : "serp_manual_edit_required",
          "market" => idea.fetch("market"),
          "market_category" => idea.fetch("market_category"),
          "business_name" => idea.fetch("business_name"),
          "problem" => idea.fetch("problem"),
          "target_customer" => idea.fetch("target_customer"),
          "customer" => idea.fetch("target_customer"),
          "offering" => idea.fetch("offering"),
          "provided_service" => idea.fetch("offering"),
          "value_proposition" => idea.fetch("value_proposition"),
          "search_demand" => search_demand_for(analysis),
          "competition" => competition_for(analysis),
          "monetization" => monetization_for(analysis, idea),
          "revenue_model" => monetization_for(analysis, idea),
          "solution" => idea.fetch("solution"),
          "launch_asset_type" => idea.fetch("launch_asset_type"),
          "lp_or_saas" => idea.fetch("launch_asset_type"),
          "lp_concept" => lp_concept_for(analysis, idea),
          "validation_plan" => validation_plan_for(analysis, idea),
          "validation_step" => validation_plan_for(analysis, idea),
          "validation_method" => validation_plan_for(analysis, idea),
          "market_analysis" => idea.fetch("market_analysis"),
          "existing_competitors" => idea.fetch("existing_competitors"),
          "differentiation" => idea.fetch("differentiation"),
          "business_name_reason" => idea.fetch("business_name_reason"),
          "business_name_quality" => idea.fetch("business_name_quality"),
          "business_idea_quality" => quality.to_h,
          "source_queries" => [ analysis.keyword ],
          "source_query" => analysis.keyword,
          "serp_run_id" => serp_run.id,
          "serp_analysis_id" => analysis.id,
          "discovery_fingerprint" => discovery_fingerprint(analysis),
          "origin_business_id" => analysis.business_id,
          "origin_business_name" => analysis.business&.name,
          "data_sources_used" => [ "serp" ],
          "data_quality" => data_quality_for(analysis),
          "missing_fields" => missing_fields_for(analysis),
          "requires_enrichment" => requires_enrichment?(analysis) || !quality.auto_publishable,
          "requires_human_edit" => !quality.auto_publishable,
          "manual_approval_required" => !quality.auto_publishable,
          "execution_mode" => "owner_decision",
          "auto_business_publish_required" => quality.auto_publishable
        }
      end

      def business_idea_quality_for(analysis, idea)
        Aicoo::Serp::BusinessIdeaQualityJudge.call(
          attributes: idea.merge(
            "revenue_model" => monetization_for(analysis, idea),
            "monetization" => monetization_for(analysis, idea),
            "validation_method" => validation_plan_for(analysis, idea),
            "validation_plan" => validation_plan_for(analysis, idea)
          ),
          source_query: analysis.keyword
        )
      end

      def duplicate_candidate?(analysis)
        fingerprint = discovery_fingerprint(analysis)
        ActionCandidate
          .where(generation_source: "serp")
          .where("metadata ->> 'candidate_kind' = ?", "new_business")
          .where(
            "metadata ->> 'discovery_fingerprint' = :fingerprint OR (metadata ->> 'source_query' = :source_query AND metadata ->> 'serp_run_id' = :serp_run_id)",
            fingerprint:,
            source_query: analysis.keyword,
            serp_run_id: serp_run.id.to_s
          )
          .exists?
      end

      def discovery_fingerprint(analysis)
        Digest::SHA256.hexdigest(
          [
            normalized_market_theme(analysis),
            analysis.keyword.to_s.squish.downcase,
            canonical_source_urls(analysis).join("|")
          ].join("::")
        )
      end

      def normalized_market_theme(analysis)
        business_idea_for(analysis).fetch("business_name").to_s.unicode_normalize(:nfkc).downcase.gsub(/\s+/, " ").strip
      end

      def canonical_source_urls(analysis)
        analysis.serp_results.order(:position).limit(5).filter_map do |result|
          uri = URI.parse(result.url.to_s)
          host = uri.host.to_s.downcase.sub(/\Awww\./, "")
          path = uri.path.to_s.sub(%r{/\z}, "")
          next if host.blank?

          "#{host}#{path}"
        rescue URI::InvalidURIError
          nil
        end.first(3)
      end

      def existing_improvement_count
        ActionCandidate
          .where(generation_source: %w[serp integrated_decision], created_at: Time.zone.today.all_day)
          .where.not(business_id: nil)
          .where.not(department: "new_business")
          .count
      end

      def serp_query_for(analysis)
        serp_query_id = analysis.raw_summary.to_h["serp_query_id"]
        return if serp_query_id.blank?

        SerpQuery.find_by(id: serp_query_id)
      end

      def market_score(analysis)
        intent_bonus = analysis.keyword.match?(MARKET_INTENT_PATTERN) ? 30 : 0
        category_bonus = serp_query_for(analysis)&.category.in?(%w[new_business keyword_discovery trend]) ? 25 : 0
        result_bonus = [ analysis.result_count.to_i * 4, 40 ].min
        competition_bonus = weak_competition?(analysis) ? 20 : 8
        intent_bonus + category_bonus + result_bonus + competition_bonus
      end

      def expected_market_value_yen(analysis)
        30_000 + ([ analysis.result_count.to_i, 10 ].min * 4_000) + (weak_competition?(analysis) ? 20_000 : 0)
      end

      def success_probability_for(analysis)
        return 0.32 if weak_competition?(analysis)

        0.24
      end

      def confidence_for(analysis)
        [ 35 + [ analysis.result_count.to_i * 3, 30 ].min, 70 ].min
      end

      def weak_competition?(analysis)
        analysis.competition_score.to_i <= 45 || analysis.serp_results.limit(5).any? { |result| result.snippet.to_s.match?(/困る|面倒|できない|口コミ|不満|代替/) }
      end

      def market_label_for(analysis)
        business_idea_for(analysis).fetch("market")
      end

      def business_idea_title(analysis)
        business_idea_for(analysis).fetch("business_name")
      end

      def business_idea_description(analysis, idea = business_idea_for(analysis))
        "#{idea.fetch("target_customer")}向けに、#{idea.fetch("problem")}を#{idea.fetch("solution")}で解決する新規事業候補です。根拠検索クエリ: #{analysis.keyword}。"
      end

      def problem_for(analysis)
        business_idea_for(analysis).fetch("problem")
      end

      def target_customer_for(analysis)
        business_idea_for(analysis).fetch("target_customer")
      end

      def search_demand_for(analysis)
        {
          "query" => analysis.keyword,
          "result_count" => analysis.result_count.to_i,
          "provider" => analysis.provider,
          "fetched_at" => analysis.analyzed_at&.iso8601
        }
      end

      def competition_for(analysis)
        {
          "competition_score" => analysis.competition_score.to_i,
          "weak_competition" => weak_competition?(analysis),
          "top_results" => analysis.serp_results.order(:position).limit(5).map do |result|
            {
              "position" => result.position,
              "title" => result.title,
              "url" => result.url,
              "snippet" => result.snippet
            }
          end
        }
      end

      def monetization_for(_analysis, idea = nil)
        solution = idea.to_h["solution"].presence || "業務支援サービス"
        "#{solution}の初期相談、月額運用、成果報酬、テンプレート販売を組み合わせて収益化する。"
      end

      def validation_plan_for(analysis, idea = business_idea_for(analysis))
        "7日以内に「#{idea.fetch("business_name")}」のLPとMVP登録導線を公開し、#{idea.fetch("target_customer")}からの登録、相談内容、CTAクリック、検索流入を確認する。根拠検索クエリはmetadata.source_queryに保存する。"
      end

      def missing_fields_for(analysis)
        idea = business_idea_for(analysis)
        values = idea.slice("market", "problem", "target_customer", "solution").merge(
          "revenue_model" => monetization_for(analysis, idea),
          "validation_plan" => validation_plan_for(analysis, idea)
        )
        values.select { |_field, value| value.blank? }.keys
      end

      def requires_enrichment?(analysis)
        missing_fields_for(analysis).any? || business_name_query_like?(business_idea_title(analysis), analysis.keyword)
      end

      def data_quality_for(analysis)
        return "sufficient" if analysis.keyword.match?(MARKET_INTENT_PATTERN) && analysis.serp_results.size >= 5

        "insufficient"
      end

      def business_idea_for(analysis)
        @business_idea_by_analysis_id ||= {}
        @business_idea_by_analysis_id[analysis.id] ||= build_business_idea(analysis)
      end

      def build_business_idea(analysis)
        query = analysis.keyword.to_s.squish
        corpus = ([ query ] + analysis.serp_results.order(:position).limit(5).flat_map { |result| [ result.title, result.snippet ] }).compact.join(" ")
        customer = infer_customer(corpus)
        service_focus = infer_service_focus(corpus, query)
        solution = solution_for(query, customer, service_focus)
        business_name = service_name_for(customer, service_focus, query)
        business_name = fallback_service_name(customer, service_focus) if business_name_query_like?(business_name, query)
        market = "#{customer}向け#{service_focus}市場"
        competitors = competitor_summaries_for(analysis)

        {
          "business_name" => business_name,
          "market" => market,
          "market_category" => market_category_for(customer, service_focus),
          "target_customer" => "#{customer}の運営者・担当者",
          "problem" => problem_statement_for(query, customer, service_focus),
          "solution" => solution,
          "offering" => solution,
          "value_proposition" => differentiation_for(customer, service_focus),
          "launch_asset_type" => launch_asset_type_for(query, service_focus),
          "market_analysis" => market_analysis_for(query, market, competitors),
          "existing_competitors" => competitors,
          "differentiation" => differentiation_for(customer, service_focus),
          "business_name_reason" => "検索語をそのまま使わず、SERP上位のtitle/snippetから顧客=#{customer}、解決策=#{service_focus}を抽出してサービス名化した。",
          "business_name_quality" => business_name_quality_for(business_name, query)
        }
      end

      def infer_customer(text)
        CUSTOMER_KEYWORDS.each do |pattern, customer|
          return customer if text.match?(pattern)
        end

        cleaned_query_tokens(text).first.presence || "小規模事業者"
      end

      def infer_service_focus(text, query)
        SERVICE_FOCUS_RULES.each do |pattern, focus|
          return focus if text.match?(pattern)
        end

        return "業務代行" if query.match?(/代行/)
        return "業務改善" if query.match?(/困る|面倒|できない/)

        "課題解決"
      end

      def solution_for(query, customer, service_focus)
        if query.match?(/代行/) || service_focus.match?(/運用|受付|制作|採用|対応/)
          "#{service_focus}代行"
        elsif query.match?(/自動化|管理|ツール|SaaS|アプリ/)
          "#{service_focus}SaaS"
        else
          "#{customer}向け#{service_focus}支援"
        end
      end

      def service_name_for(customer, service_focus, query)
        suffix = if query.match?(/代行/)
          "代行"
        elsif query.match?(/自動化|管理|ツール|SaaS|アプリ/)
          "ツール"
        elsif query.match?(/比較|おすすめ/)
          "比較ナビ"
        else
          "支援"
        end

        focus = service_focus.sub(/代行\z/, "")
        "#{customer}#{focus}#{suffix}".squish
      end

      def fallback_service_name(customer, service_focus)
        "#{customer}#{service_focus}支援"
      end

      def problem_statement_for(query, customer, service_focus)
        if query.match?(/困る|面倒|できない/)
          "#{customer}が#{service_focus}を自力で運用できず、時間と機会損失が発生している"
        elsif query.match?(/比較|料金|おすすめ/)
          "#{customer}が#{service_focus}の外注先やツールを比較しても、自社に合う選択肢を判断しづらい"
        else
          "#{customer}が#{service_focus}に必要な作業を継続できず、集客・予約・売上改善につながっていない"
        end
      end

      def market_analysis_for(query, market, competitors)
        {
          "source_query" => query,
          "market" => market,
          "serp_result_count" => competitors.size,
          "observed_competitor_titles" => competitors.map { |competitor| competitor["title"] }.first(5)
        }
      end

      def competitor_summaries_for(analysis)
        analysis.serp_results.order(:position).limit(5).map do |result|
          {
            "position" => result.position,
            "title" => result.title.to_s.squish,
            "url" => result.url.to_s,
            "snippet" => result.snippet.to_s.squish
          }
        end
      end

      def differentiation_for(customer, service_focus)
        "#{customer}に対象を絞り、#{service_focus}の相談受付から初期実行までを小さく代行して、汎用比較サイトより実行完了に近い導線を提供する。"
      end

      def lp_concept_for(_analysis, idea)
        "#{idea.fetch("target_customer")}に、#{idea.fetch("problem")}を明示し、#{idea.fetch("solution")}の事前相談・MVP登録を受け付ける。"
      end

      def market_category_for(customer, service_focus)
        [ customer, service_focus ].join("/")
      end

      def launch_asset_type_for(query, service_focus)
        return "saas" if query.match?(/SaaS|ツール|アプリ|自動化|管理/) || service_focus.match?(/管理|自動化|予約受付|問い合わせ対応/)

        "lp"
      end

      def business_name_quality_for(name, query)
        {
          "query_reused_as_name" => business_name_query_like?(name, query),
          "understandable_service_name" => understandable_service_name?(name),
          "checked_at" => Time.current.iso8601
        }
      end

      def business_name_query_like?(name, query)
        normalized_name = normalize_name_for_comparison(name.to_s.sub(QUERY_NAME_SUFFIX_PATTERN, ""))
        normalized_query = normalize_name_for_comparison(query)
        normalized_name == normalized_query || name.to_s.include?("の検証事業")
      end

      def understandable_service_name?(name)
        name.match?(/代行|支援|ツール|SaaS|受付|制作|運用|管理|ナビ|相談|改善|採用|集客/)
      end

      def normalize_name_for_comparison(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]]+/, "").strip
      end

      def cleaned_query_tokens(text)
        text.to_s.unicode_normalize(:nfkc).split(/[\s　]+/).map(&:squish).reject do |token|
          token.blank? || REGION_WORDS.include?(token) || INTENT_WORDS.include?(token) || token.match?(/https?:/)
        end
      end
    end
  end
end
