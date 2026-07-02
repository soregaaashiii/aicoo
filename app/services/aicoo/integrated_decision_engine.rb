module Aicoo
  class IntegratedDecisionEngine
    Summary = Data.define(
      :serp_run,
      :daily_run,
      :top_business,
      :candidate_count,
      :new_business_candidate_count,
      :expected_profit_yen,
      :message
    )

    def initialize(serp_run: SerpRun.recent.first, daily_run: AicooDailyRun.recent.first)
      @serp_run = serp_run
      @daily_run = daily_run
    end

    def summary
      business = top_business
      Summary.new(
        serp_run:,
        daily_run:,
        top_business: business,
        candidate_count: integrated_candidates.count,
        new_business_candidate_count: new_business_candidates.count,
        expected_profit_yen: integrated_candidates.maximum(:expected_profit_yen).to_i,
        message: message_for(business)
      )
    end

    def generate_unified_candidates!
      return [] unless serp_run&.successful? || serp_run&.status == "partial_failed"

      candidates = []
      serp_run.serp_analyses.successful.includes(:business).group_by(&:business).each do |business, analyses|
        next unless business
        next if duplicate_today?(business, "existing_business_improvement")

        best_analysis = analyses.max_by { |analysis| analysis.result_count.to_i }
        candidates << business.action_candidates.create!(
          title: "#{business.name}の市場観測と内部データを統合して改善する",
          description: "SERP市場観測とDaily Runの内部データを合わせ、検索意図・CTR・CV・改善履歴を見て優先改善を決めます。",
          action_type: "seo_improvement",
          department: "revenue",
          generation_source: "integrated_decision",
          status: "idea",
          immediate_value_yen: 20_000,
          success_probability: 0.35,
          expected_hours: 1.5,
          confidence_score: 45,
          data_confidence_score: 50,
          priority_score: 65,
          execution_prompt: prompt_for(business, best_analysis),
          evaluation_reason: "integrated_decision:serp_and_daily",
          metadata: {
            "source" => "integrated_decision",
            "candidate_kind" => "existing_business_improvement",
            "serp_run_id" => serp_run.id,
            "aicoo_daily_run_id" => daily_run&.id,
            "source_query" => best_analysis.keyword,
            "serp_result_count" => best_analysis.result_count,
            "daily_action_candidates_generated_count" => daily_run&.action_candidates_generated_count.to_i
          }
        )
      end
      candidates.concat(generate_new_business_candidates!)
      candidates
    end

    private

    attr_reader :serp_run, :daily_run

    def integrated_candidates
      ActionCandidate.where(generation_source: "integrated_decision")
    end

    def new_business_candidates
      integrated_candidates.where(
        "department = :department OR metadata ->> 'candidate_kind' = :kind",
        department: "new_business",
        kind: "new_business"
      )
    end

    def top_business
      integrated_candidates.active_for_ranking.by_recommendation.first&.business ||
        serp_run&.serp_analyses&.successful&.includes(:business)&.first&.business
    end

    def duplicate_today?(business, candidate_kind)
      business.action_candidates
              .where(generation_source: "integrated_decision", created_at: Time.zone.today.all_day)
              .where("metadata ->> 'candidate_kind' = ?", candidate_kind)
              .exists?
    end

    def generate_new_business_candidates!
      serp_run.serp_analyses.successful.includes(:business, :serp_results).filter_map do |analysis|
        next unless new_business_analysis?(analysis)
        next if duplicate_new_business_today?(analysis)

        analysis.business.action_candidates.create!(
          title: new_business_title(analysis),
          description: new_business_description(analysis),
          action_type: "build_lp",
          department: "new_business",
          generation_source: "integrated_decision",
          status: "idea",
          immediate_value_yen: new_business_value_yen(analysis),
          success_probability: 0.28,
          expected_hours: 2.5,
          cost_yen: 0,
          confidence_score: 42,
          data_confidence_score: 45,
          priority_score: 70,
          execution_prompt: new_business_prompt(analysis),
          evaluation_reason: "integrated_decision:new_business_from_serp",
          metadata: {
            "source" => "integrated_decision",
            "candidate_kind" => "new_business",
            "serp_run_id" => serp_run.id,
            "aicoo_daily_run_id" => daily_run&.id,
            "source_query" => analysis.keyword,
            "serp_analysis_id" => analysis.id,
            "serp_result_count" => analysis.result_count,
            "problem" => "検索クエリ「#{analysis.keyword}」で探している課題を、低コストLPで検証する",
            "target_customer" => "検索クエリ「#{analysis.keyword}」で解決策を探しているユーザー",
            "revenue_model" => "初期はリード獲得/問い合わせ/紹介。反応後にSaaS・広告・成果報酬を判定",
            "validation_step" => "7日以内にLPを公開し、CTAクリック/CV/検索流入を確認する",
            "market_memo" => market_memo_for(analysis),
            "recommendation_reason" => "SERPに市場需要の兆候があり、LP検証なら小さく試せるため"
          }
        )
      end
    end

    def new_business_analysis?(analysis)
      serp_query = serp_query_for(analysis)
      return true if serp_query&.category.in?(%w[new_business keyword_discovery trend])

      query = analysis.keyword.to_s
      query.match?(/AI|SaaS|自動化|代行|ツール|アプリ|比較|課題|効率化|生成|管理/i)
    end

    def duplicate_new_business_today?(analysis)
      ActionCandidate
        .where(generation_source: "integrated_decision", created_at: Time.zone.today.all_day)
        .where("metadata ->> 'candidate_kind' = ?", "new_business")
        .where("metadata ->> 'source_query' = ?", analysis.keyword)
        .exists?
    end

    def serp_query_for(analysis)
      serp_query_id = analysis.raw_summary.to_h["serp_query_id"]
      return if serp_query_id.blank?

      SerpQuery.find_by(id: serp_query_id)
    end

    def new_business_title(analysis)
      "新規事業候補: #{analysis.keyword}"
    end

    def new_business_description(analysis)
      "SERP検索クエリ「#{analysis.keyword}」から、LP検証で小さく始められる新規事業候補を見つけました。"
    end

    def new_business_value_yen(analysis)
      base = 45_000
      bonus = [ analysis.result_count.to_i, 10 ].min * 3_000
      base + bonus
    end

    def market_memo_for(analysis)
      top_titles = analysis.serp_results.order(:position).limit(3).pluck(:title).compact
      return "競合/市場メモはSERP結果詳細で確認してください。" if top_titles.empty?

      "上位結果: #{top_titles.join(' / ')}"
    end

    def new_business_prompt(analysis)
      <<~PROMPT.squish
        SERP検索クエリ「#{analysis.keyword}」を根拠に、新規事業のLP検証を行ってください。まずはMVP開発ではなく、課題、想定顧客、価値提案、CTA、検証指標を整理し、AICOOの公開LP基盤でdraft LPを作る前提の仕様にしてください。
      PROMPT
    end

    def prompt_for(business, analysis)
      <<~PROMPT.squish
        #{business.name}について、SERP検索クエリ「#{analysis.keyword}」の市場観測結果とDaily RunのGA4/GSC/Revenue/Learningを統合して、最も期待値が高い改善案を1つ実装してください。SERP単独判断は禁止し、内部データと改善履歴を必ず確認してください。
      PROMPT
    end

    def message_for(business)
      return "SERP RunとDaily Runの統合判断対象はまだありません。" unless business

      "#{business.name}を最重要Businessとして、SERP市場観測と内部データを統合して判断します。"
    end
  end
end
