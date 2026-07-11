module Aicoo
  module Serp
    class NewBusinessDiscoveryGenerator
      Result = Data.define(:candidates, :created_count, :duplicate_count, :failed_count, :existing_improvement_count, :errors)

      MARKET_INTENT_PATTERN = /困る|面倒|代行|比較|料金|おすすめ|できない|自動化|管理|テンプレート|法人|個人事業主|AI|SaaS|ツール|アプリ|予約|確認|チェック|作成|生成/i

      def initialize(serp_run:, limit: 10)
        @serp_run = serp_run
        @limit = limit.to_i.positive? ? limit.to_i : 10
        @errors = []
        @duplicate_count = 0
      end

      def call
        candidates = discoverable_analyses.first(limit).filter_map { |analysis| create_candidate_for(analysis) }
        Result.new(
          candidates:,
          created_count: candidates.size,
          duplicate_count: duplicate_count,
          failed_count: errors.size,
          existing_improvement_count: existing_improvement_count,
          errors: errors.first(10)
        )
      end

      private

      attr_reader :serp_run, :limit, :errors
      attr_accessor :duplicate_count

      def discoverable_analyses
        serp_run.serp_analyses
                .successful
                .includes(:business, :serp_results)
                .to_a
                .select { |analysis| market_discovery_analysis?(analysis) }
                .sort_by { |analysis| -market_score(analysis) }
      end

      def market_discovery_analysis?(analysis)
        return false if analysis.keyword.blank?
        return false if branded_existing_business_query?(analysis)
        serp_query = serp_query_for(analysis)
        return true if serp_query&.category.in?(%w[new_business keyword_discovery trend])
        return false if serp_query.present?

        analysis.keyword.match?(MARKET_INTENT_PATTERN)
      end

      def branded_existing_business_query?(analysis)
        return false unless analysis.business

        Aicoo::Serp::ResultRelevance.new(business: analysis.business, query: analysis.keyword).branded_query?
      end

      def create_candidate_for(analysis)
        if duplicate_candidate?(analysis)
          self.duplicate_count += 1
          return nil
        end

        candidate = ActionCandidate.create!(candidate_attributes(analysis))
        candidate.reload
        return candidate if candidate.business_id.present?

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

      def candidate_attributes(analysis)
        {
          business: nil,
          title: business_idea_title(analysis),
          description: business_idea_description(analysis),
          action_type: "new_business",
          department: "new_business",
          generation_source: "serp",
          status: "idea",
          immediate_value_yen: expected_market_value_yen(analysis),
          success_probability: success_probability_for(analysis),
          expected_hours: 2.0,
          cost_yen: 0,
          confidence_score: confidence_for(analysis),
          data_confidence_score: confidence_for(analysis),
          priority_score: [ market_score(analysis), 95 ].min,
          execution_prompt: validation_plan_for(analysis),
          evaluation_reason: "serp:new_business_discovery",
          metadata: candidate_metadata(analysis)
        }
      end

      def candidate_metadata(analysis)
        {
          "source" => "serp",
          "candidate_kind" => "new_business",
          "business_flow" => "serp_auto_added",
          "market" => market_label_for(analysis),
          "business_name" => business_idea_title(analysis),
          "problem" => problem_for(analysis),
          "target_customer" => target_customer_for(analysis),
          "search_demand" => search_demand_for(analysis),
          "competition" => competition_for(analysis),
          "monetization" => monetization_for(analysis),
          "revenue_model" => monetization_for(analysis),
          "validation_plan" => validation_plan_for(analysis),
          "validation_step" => validation_plan_for(analysis),
          "source_queries" => [ analysis.keyword ],
          "source_query" => analysis.keyword,
          "serp_run_id" => serp_run.id,
          "serp_analysis_id" => analysis.id,
          "origin_business_id" => analysis.business_id,
          "origin_business_name" => analysis.business&.name,
          "data_sources_used" => [ "serp" ],
          "execution_mode" => "owner_decision",
          "auto_business_publish_required" => true
        }
      end

      def duplicate_candidate?(analysis)
        ActionCandidate
          .where(generation_source: "serp")
          .where("metadata ->> 'candidate_kind' = ?", "new_business")
          .where("metadata ->> 'source_query' = ?", analysis.keyword)
          .where(created_at: Time.zone.today.all_day)
          .exists?
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
        analysis.keyword.to_s.squish
      end

      def business_idea_title(analysis)
        "#{market_label_for(analysis)}の検証事業"
      end

      def business_idea_description(analysis)
        "検索需要「#{analysis.keyword}」を起点に、LP/MVPで小さく検証する新規事業候補です。"
      end

      def problem_for(analysis)
        "検索ユーザーは「#{analysis.keyword}」に関する比較、料金、代替、方法、困りごとの解決策を探しています。"
      end

      def target_customer_for(analysis)
        "「#{analysis.keyword}」で検索し、既存サービスでは解決策を選び切れていない個人または法人"
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

      def monetization_for(_analysis)
        "初期はLPでリード獲得を検証し、反応があれば紹介、成果報酬、月額課金、代行の順に収益化を検討する。"
      end

      def validation_plan_for(analysis)
        "7日以内に「#{analysis.keyword}」向けLPを公開し、CTAクリック、問い合わせ、検索流入、広告テスト反応を確認する。"
      end
    end
  end
end
