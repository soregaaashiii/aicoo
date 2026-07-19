module Aicoo
  class ArticleOpportunityAnalyzer
    class SnapshotRunner
      SOURCE_TYPE = "article_analytics".freeze
      MODEL_NAME = "article_opportunity_analyzer_snapshot_v1".freeze
      TERMINAL_CANDIDATE_STATUS = "archived".freeze

      Result = Data.define(
        :mode,
        :business,
        :snapshot_count,
        :article_count,
        :analyzed_count,
        :action_candidate_count,
        :created_count,
        :failed_count,
        :article_results,
        :candidate_ids
      )

      ArticleResult = Data.define(
        :snapshot_id,
        :article_id,
        :title,
        :normalized_path,
        :opportunity_score,
        :score_breakdown,
        :opportunities,
        :candidate_drafts,
        :metadata
      )

      CandidateDraft = Data.define(
        :title,
        :action_type,
        :description,
        :execution_prompt,
        :metadata
      )

      def initialize(business:, apply: false, limit: nil)
        @business = business
        @apply = ActiveModel::Type::Boolean.new.cast(apply)
        @limit = limit&.to_i
        @created_count = 0
        @failed_count = 0
        @candidate_ids = []
      end

      def call
        results = snapshots.filter_map { |snapshot| analyze_snapshot(snapshot) }
        persist_candidates!(results) if apply

        Result.new(
          mode: apply ? "apply" : "dry-run",
          business:,
          snapshot_count: snapshots.size,
          article_count: results.size,
          analyzed_count: results.size,
          action_candidate_count: results.sum { |result| result.candidate_drafts.size },
          created_count:,
          failed_count:,
          article_results: results,
          candidate_ids:
        )
      end

      private

      attr_reader :business, :apply, :limit, :created_count, :failed_count, :candidate_ids

      def snapshots
        @snapshots ||= begin
          scope = AicooDataSnapshot.where(source_type: SOURCE_TYPE).recent
          rows = scope.select do |snapshot|
            payload = snapshot.payload.to_h.deep_stringify_keys
            next false unless payload["business_id"].to_i == business.id
            next false if payload["snapshot_status"].to_s.in?(%w[archived ignored])
            next false unless payload["article_id"].present?

            true
          end
          limit.to_i.positive? ? rows.first(limit) : rows
        end
      end

      def analyze_snapshot(snapshot)
        payload = snapshot.payload.to_h.deep_stringify_keys
        breakdown = score_breakdown(payload)
        score = breakdown.except("learning_confidence").values.sum
        score += breakdown["learning_confidence"]
        score = clamp(score, 0, 100).round
        opportunities = opportunities_for(payload, breakdown)
        drafts = opportunities.map { |opportunity| candidate_draft(snapshot, payload, opportunity, score, breakdown) }

        ArticleResult.new(
          snapshot_id: snapshot.id,
          article_id: payload["article_id"],
          title: payload.dig("article", "title").presence || payload["slug"].to_s,
          normalized_path: payload["normalized_path"],
          opportunity_score: score,
          score_breakdown: breakdown,
          opportunities:,
          candidate_drafts: drafts,
          metadata: analysis_metadata(snapshot, payload, score, breakdown, opportunities)
        )
      rescue StandardError => e
        @failed_count += 1
        Rails.logger.warn("[Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner] skipped snapshot_id=#{snapshot.id} #{e.class}: #{e.message}")
        nil
      end

      def score_breakdown(payload)
        {
          "seo_opportunity" => seo_score(payload),
          "ctr_opportunity" => ctr_score(payload),
          "pv_opportunity" => pv_score(payload),
          "click_opportunity" => click_score(payload),
          "content_opportunity" => content_score(payload),
          "learning_confidence" => learning_score(payload)
        }
      end

      def seo_score(payload)
        gsc = payload["gsc"].to_h
        return 0 unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        query_count = decimal(gsc["query_count"])
        rank_delta = decimal(first_present(gsc["rank_delta"], gsc["position_delta"], gsc["average_position_delta"]))
        demand = clamp(impressions / 5_000, 0, 1) * 10
        rank_gap = if position > 20
                     12
                   elsif position > 10
                     9
                   elsif position > 5
                     5
                   else
                     1
                   end
        rank_trend = if rank_delta.negative?
                       3
                     elsif rank_delta.positive?
                       1
                     else
                       0
                     end
        query_depth = clamp(query_count / 10, 0, 1) * 3
        (demand + rank_gap + query_depth + rank_trend).round(1)
      end

      def ctr_score(payload)
        gsc = payload["gsc"].to_h
        return 0 unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        ctr = decimal(gsc["ctr"])
        return 0 if impressions < 100

        target = target_ctr(decimal(gsc["average_position"]))
        gap = [ target - ctr, 0.to_d ].max
        (clamp(gap / 0.03, 0, 1) * 20).round(1)
      end

      def pv_score(payload)
        ga4 = payload["ga4"].to_h
        return 0 unless ga4["available"]

        pageviews = decimal(ga4["pageviews"])
        active_users = decimal(ga4["active_users"])
        sessions = decimal(ga4["sessions"])
        engagement = decimal(ga4["engagement_seconds"])
        pv_delta = decimal(first_present(ga4["pageviews_delta"], ga4["pv_delta"], ga4["pageviews_change"]))
        traffic = clamp(pageviews / 1_000, 0, 1) * 7
        user_depth = pageviews.positive? ? clamp(active_users / pageviews, 0, 1) * 4 : 0
        session_depth = sessions.positive? ? clamp(pageviews / sessions, 0, 2) / 2 * 3 : 0
        engagement_depth = pageviews.positive? ? clamp((engagement / pageviews) / 90, 0, 1) * 6 : 0
        pv_trend = pv_delta.negative? ? 3 : 0
        (traffic + user_depth + session_depth + engagement_depth + pv_trend).round(1)
      end

      def click_score(payload)
        ga4 = payload["ga4"].to_h
        shop_click = payload["shop_click"].to_h
        return 0 unless ga4["available"] || shop_click["available"]

        pageviews = decimal(ga4["pageviews"])
        total_clicks = decimal(shop_click["total_clicks"])
        rate = pageviews.positive? ? total_clicks / pageviews : 0.to_d
        gap = clamp(0.04.to_d - rate, 0, 0.04)
        traffic_basis = clamp(pageviews / 1_000, 0, 1)
        (gap / 0.04 * 15 * [ traffic_basis, 0.25 ].max).round(1)
      end

      def content_score(payload)
        article = payload["article"].to_h
        score = 0.to_d
        word_count = decimal(article["word_count"])
        internal_links = decimal(article["internal_link_count"])
        shop_count = decimal(article["shop_count"])
        verified_shop_count = decimal(article["verified_shop_count"])

        score += 7 if word_count.positive? && word_count < 1_500
        score += 5 if internal_links.zero?
        score += 5 if shop_count.positive? && shop_count < 5
        score += 5 if shop_count.positive? && verified_shop_count < shop_count
        score.round(1)
      end

      def learning_score(payload)
        learning = payload["learning"].to_h
        improvements = decimal(learning["improvement_count"])
        successes = decimal(learning["improvement_success_count"])
        return 2 if improvements.zero?

        success_rate = successes / improvements
        (2 + clamp(success_rate, 0, 1) * 8).round(1)
      end

      def opportunities_for(payload, breakdown)
        rows = []
        rows << opportunity("ctr_improvement", "CTR改善", "タイトル・metaを見直す", breakdown["ctr_opportunity"]) if breakdown["ctr_opportunity"] >= 8
        rows << opportunity("rank_improvement", "順位改善", "検索意図に合わせて本文を更新する", breakdown["seo_opportunity"]) if breakdown["seo_opportunity"] >= 12
        rows << opportunity("internal_link_addition", "内部リンク追加", "関連記事・店舗ページへの内部リンクを追加する", breakdown["content_opportunity"]) if internal_link_gap?(payload)
        rows << opportunity("shop_addition", "店舗追加", "記事テーマに合う掲載店舗を追加する", breakdown["content_opportunity"]) if shop_gap?(payload)
        rows << opportunity("verified_shop_addition", "確認済店舗追加", "未確認店舗の喫煙情報を確認する", breakdown["content_opportunity"]) if verified_shop_gap?(payload)
        rows << opportunity("content_update", "本文更新", "本文量と最新性を補強する", breakdown["content_opportunity"]) if content_gap?(payload)
        rows << opportunity("cta_improvement", "送客CTA改善", "店舗送客CTAを見直す", breakdown["click_opportunity"]) if breakdown["click_opportunity"] >= 6
        rows.presence || [ opportunity("monitoring", "継続観測", "現状の実績を継続観測する", 0) ]
      end

      def opportunity(type, label, next_action, score)
        {
          "opportunity_type" => type,
          "label" => label,
          "next_action" => next_action,
          "score" => score.to_f.round(1)
        }
      end

      def candidate_draft(snapshot, payload, opportunity, score, breakdown)
        title = "#{article_title(payload)}の#{opportunity['label']}を行う"
        CandidateDraft.new(
          title:,
          action_type: action_type_for(opportunity),
          description: "#{payload['normalized_path']} のArticleAnalyticsSnapshotから #{opportunity['label']} Opportunity を検出しました。",
          execution_prompt: opportunity["next_action"],
          metadata: analysis_metadata(snapshot, payload, score, breakdown, [ opportunity ]).merge(
            "opportunity_type" => opportunity["opportunity_type"],
            "opportunity_label" => opportunity["label"],
            "next_action" => opportunity["next_action"],
            "opportunity_score_component" => opportunity["score"]
          )
        )
      end

      def persist_candidates!(results)
        results.each do |result|
          result.candidate_drafts.each do |draft|
            candidate = business.action_candidates.create!(
              title: draft.title,
              action_type: draft.action_type,
              status: TERMINAL_CANDIDATE_STATUS,
              generation_source: "business_analyzer",
              department: "general",
              immediate_value_yen: 0,
              expected_profit_yen: 0,
              expected_revenue_value_yen: 0,
              expected_total_value_yen: 0,
              final_expected_value_yen: 0,
              success_probability: 0,
              description: draft.description,
              execution_prompt: draft.execution_prompt,
              metadata: draft.metadata.merge(
                "experimental_only" => true,
                "today_connected" => false,
                "codex_connected" => false,
                "archived_reason" => "article_opportunity_analyzer_comparison_only"
              )
            )
            @created_count += 1
            @candidate_ids << candidate.id
          rescue StandardError => e
            @failed_count += 1
            Rails.logger.warn("[Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner] candidate create failed snapshot_id=#{result.snapshot_id} #{e.class}: #{e.message}")
          end
        end
      end

      def analysis_metadata(snapshot, payload, score, breakdown, opportunities)
        {
          "value_model_name" => MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => snapshot.id,
          "article_id" => payload["article_id"],
          "article_path" => payload["normalized_path"],
          "opportunity_score" => score,
          "score_breakdown" => breakdown,
          "opportunities" => opportunities,
          "evidence" => evidence(payload),
          "expected_profit_yen" => nil,
          "expected_profit_calculated" => false,
          "calculated_at" => Time.current.iso8601
        }
      end

      def evidence(payload)
        {
          "gsc" => payload["gsc"].to_h.slice("available", "impressions", "clicks", "ctr", "average_position", "query_count", "top_queries", "rank_delta", "position_delta", "average_position_delta"),
          "ga4" => payload["ga4"].to_h.slice("available", "pageviews", "active_users", "sessions", "engagement_seconds", "pageviews_delta", "pv_delta", "pageviews_change"),
          "shop_click" => payload["shop_click"].to_h.slice("available", "total_clicks", "article_shop_clicks", "phone_clicks", "map_clicks", "affiliate_clicks"),
          "article" => payload["article"].to_h.slice("title", "word_count", "internal_link_count", "shop_count", "verified_shop_count", "content_source"),
          "learning" => payload["learning"].to_h.slice("improvement_count", "improvement_success_count", "last_improvement_at")
        }
      end

      def action_type_for(opportunity)
        case opportunity["opportunity_type"]
        when "shop_addition", "verified_shop_addition"
          "smoking_info_verify"
        else
          "article_update"
        end
      end

      def article_title(payload)
        payload.dig("article", "title").to_s.presence || payload["slug"].to_s.presence || payload["normalized_path"].to_s
      end

      def target_ctr(position)
        if position.positive? && position <= 5
          0.04.to_d
        elsif position.positive? && position <= 10
          0.03.to_d
        elsif position.positive? && position <= 20
          0.02.to_d
        else
          0.012.to_d
        end
      end

      def internal_link_gap?(payload)
        payload.dig("article", "internal_link_count").to_i.zero?
      end

      def shop_gap?(payload)
        shop_count = decimal(payload.dig("article", "shop_count"))
        shop_count.positive? && shop_count < 5
      end

      def verified_shop_gap?(payload)
        shop_count = decimal(payload.dig("article", "shop_count"))
        verified = decimal(payload.dig("article", "verified_shop_count"))
        shop_count.positive? && verified < shop_count
      end

      def content_gap?(payload)
        word_count = decimal(payload.dig("article", "word_count"))
        word_count.positive? && word_count < 1_500
      end

      def decimal(value)
        value.to_s.delete(",").to_d
      end

      def first_present(*values)
        values.find { |value| value.present? }
      end

      def clamp(value, min, max)
        [[ value.to_d, min.to_d ].max, max.to_d ].min
      end
    end
  end
end
