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
        :search_demand_score,
        :improvement_potential_score,
        :expected_improvement_score,
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
        results = results.sort_by { |result| [ -result.expected_improvement_score.to_d, -result.opportunity_score.to_d, result.normalized_path.to_s ] }
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

      def score_diagnostics
        snapshots.filter_map do |snapshot|
          payload = snapshot.payload.to_h.deep_stringify_keys
          breakdown = score_breakdown(payload)
          search_demand = search_demand_score(payload)
          improvement_potential = improvement_potential_score(breakdown)
          opportunities = opportunities_for(payload, breakdown)
          opportunities = opportunities.map { |opportunity| enrich_opportunity(opportunity, payload, search_demand, improvement_potential) }
          primary = primary_opportunity(opportunities)
          expected_improvement = decimal(primary&.dig("expected_improvement_score"))
          gsc = gsc_metrics(payload)
          ga4 = ga4_metrics(payload)
          shop_click = shop_click_metrics(payload)
          relative = relative_metrics_for(payload)

          {
            "article_id" => payload["article_id"],
            "title" => payload.dig("article", "title").presence || payload["slug"].to_s,
            "snapshot_id" => snapshot.id,
            "gsc" => gsc,
            "ga4" => ga4,
            "shop_click" => shop_click,
            "business_relative" => relative,
            "seo_opportunity" => breakdown["seo_opportunity"],
            "seo_condition_result" => breakdown["seo_opportunity"].to_d.positive? ? "eligible" : "not_eligible",
            "seo_reason" => seo_reason(payload),
            "ctr_opportunity" => breakdown["ctr_opportunity"],
            "ctr_condition_result" => breakdown["ctr_opportunity"].to_d.positive? ? "eligible" : "not_eligible",
            "ctr_reason" => ctr_reason(payload),
            "search_demand_score" => search_demand,
            "search_demand_breakdown" => search_demand_breakdown(payload),
            "improvement_potential_score" => improvement_potential,
            "improvement_potential_breakdown" => {
              "seo" => breakdown["seo_opportunity"],
              "ctr" => breakdown["ctr_opportunity"],
              "pv" => breakdown["pv_opportunity"],
              "click" => breakdown["click_opportunity"],
              "content" => breakdown["content_opportunity"],
              "learning" => breakdown["learning_confidence"]
            },
            "expected_improvement_score" => expected_improvement.to_f.round(2),
            "expected_improvement_formula" => {
              "search_demand_score" => search_demand,
              "improvement_potential_score" => improvement_potential,
              "business_value" => primary&.dig("business_value"),
              "success_probability" => primary&.dig("success_probability"),
              "estimated_work_hours" => primary&.dig("estimated_work_hours")
            }
          }
        rescue StandardError => e
          Rails.logger.warn("[Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner] diagnostic skipped snapshot_id=#{snapshot.id} #{e.class}: #{e.message}")
          nil
        end
      end

      def business_score_statistics
        business_statistics
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
        search_demand_score = search_demand_score(payload)
        improvement_potential_score = improvement_potential_score(breakdown)
        opportunities = opportunities.map { |opportunity| enrich_opportunity(opportunity, payload, search_demand_score, improvement_potential_score) }
        expected_improvement_score = opportunities.map { |opportunity| decimal(opportunity["expected_improvement_score"]) }.max || 0.to_d
        drafts = opportunities.map { |opportunity| candidate_draft(snapshot, payload, opportunity, score, breakdown) }

        ArticleResult.new(
          snapshot_id: snapshot.id,
          article_id: payload["article_id"],
          title: payload.dig("article", "title").presence || payload["slug"].to_s,
          normalized_path: payload["normalized_path"],
          opportunity_score: score,
          search_demand_score: search_demand_score.to_f.round(2),
          improvement_potential_score: improvement_potential_score.to_f.round(2),
          expected_improvement_score: expected_improvement_score.to_f.round(2),
          score_breakdown: breakdown,
          opportunities:,
          candidate_drafts: drafts,
          metadata: analysis_metadata(snapshot, payload, score, search_demand_score, improvement_potential_score, expected_improvement_score, breakdown, opportunities)
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
        gsc = gsc_metrics(payload)
        return 0 unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        query_count = decimal(gsc["query_count"])
        rank_delta = decimal(first_present(gsc["rank_delta"], gsc["position_delta"], gsc["average_position_delta"]))
        relative = relative_metrics_for(payload)
        return 0 if impressions.zero? || position.zero? || position > 50

        demand_factor = relative["impression_percentile"].to_d
        rank_factor = if position >= 11 && position <= 20
                        1.to_d
                      elsif position > 20 && position <= 30
                        0.55.to_d
                      elsif position > 5 && position <= 10
                        0.45.to_d
                      elsif position > 30 && impressions >= 1_000
                        0.25.to_d
                      else
                        0.1.to_d
                      end
        relative_ctr_gap = relative["ctr_gap_to_business"].to_d
        rank_median_boost = position >= 11 && position <= 20 && relative["impressions_at_or_above_median"] ? 0.35.to_d : 0.to_d
        ctr_factor = [ relative_ctr_gap, rank_median_boost ].max
        rank_trend = if rank_delta.negative?
                       0.15.to_d
                     elsif rank_delta.positive?
                       0.05.to_d
                     else
                       0.to_d
                     end
        query_depth = clamp(query_count / 10, 0, 1) * 0.1
        (25 * demand_factor * (rank_factor + ctr_factor + rank_trend + query_depth).clamp(0, 1)).round(1)
      end

      def ctr_score(payload)
        gsc = gsc_metrics(payload)
        return 0 unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        relative = relative_metrics_for(payload)
        return 0 if impressions.zero? || position.zero? || position > 50

        ctr_gap = relative["ctr_gap_to_business"].to_d
        return 0 unless ctr_gap.positive?

        impact = relative["impression_percentile"].to_d
        rank_relevance = position <= 30 ? 1.to_d : 0.35.to_d
        (25 * impact * ctr_gap * rank_relevance).round(1)
      end

      def pv_score(payload)
        ga4 = ga4_metrics(payload)
        return 0 unless ga4["available"]

        pageviews = decimal(ga4["pageviews"])
        active_users = decimal(ga4["active_users"])
        sessions = decimal(ga4["sessions"])
        engagement = decimal(ga4["engagement_seconds"])
        pv_delta = decimal(first_present(ga4["pageviews_delta"], ga4["pv_delta"], ga4["pageviews_change"]))
        return 0 if pageviews < 50

        traffic_impact = clamp(pageviews / 1_500, 0, 1)
        active_rate = pageviews.positive? ? active_users / pageviews : 0.to_d
        engagement_per_view = pageviews.positive? ? engagement / pageviews : 0.to_d
        session_depth = sessions.positive? ? pageviews / sessions : 0.to_d
        engagement_gap = clamp((45.to_d - engagement_per_view) / 45, 0, 1)
        active_gap = clamp((0.35.to_d - active_rate) / 0.35, 0, 1)
        session_gap = clamp((1.2.to_d - session_depth) / 1.2, 0, 1)
        decline_gap = pv_delta.negative? ? clamp(pv_delta.abs / [ pageviews, 1.to_d ].max, 0, 1) : 0.to_d
        improvement_gap = [ engagement_gap, active_gap, session_gap, decline_gap ].max
        (15 * traffic_impact * improvement_gap).round(1)
      end

      def click_score(payload)
        ga4 = ga4_metrics(payload)
        shop_click = shop_click_metrics(payload)
        return 0 unless ga4["available"] || shop_click["available"]

        pageviews = decimal(ga4["pageviews"])
        total_clicks = decimal(shop_click["total_clicks"])
        return 0 if pageviews < 50

        rate = pageviews.positive? ? total_clicks / pageviews : 0.to_d
        gap = clamp(0.04.to_d - rate, 0, 0.04)
        recoverable_clicks = pageviews * gap
        traffic_basis = clamp(recoverable_clicks / 40, 0, 1)
        (20 * traffic_basis).round(1)
      end

      def content_score(payload)
        article = payload["article"].to_h
        word_count = decimal(article["word_count"])
        internal_links = decimal(article["internal_link_count"])
        shop_count = decimal(article["shop_count"])
        verified_shop_count = decimal(article["verified_shop_count"])
        word_gap = word_count.positive? ? clamp((2_500 - word_count) / 2_500, 0, 1) : 0.to_d
        link_gap = clamp((3 - internal_links) / 3, 0, 1)
        shop_gap = shop_count.positive? ? clamp((8 - shop_count) / 8, 0, 1) : 0.to_d
        verified_gap = shop_count.positive? ? clamp((shop_count - verified_shop_count) / shop_count, 0, 1) : 0.to_d

        ((word_gap * 6) + (link_gap * 5) + (shop_gap * 5) + (verified_gap * 4)).round(1)
      end

      def learning_score(payload)
        learning = payload["learning"].to_h
        improvements = decimal(learning["improvement_count"])
        successes = decimal(learning["improvement_success_count"])
        last_improvement_at = parse_time(learning["last_improvement_at"])
        return 1 if improvements.zero?

        success_rate = successes / improvements
        recency_penalty = last_improvement_at && last_improvement_at > 30.days.ago ? 3 : 0
        (2 + clamp(success_rate, 0, 1) * 8 - recency_penalty).clamp(0, 10).round(1)
      end

      def opportunities_for(payload, breakdown)
        rows = []
        reasons = score_reasons(payload)
        rows << opportunity("ctr_improvement", "CTR改善", "タイトル・metaを見直す", breakdown["ctr_opportunity"], reasons["ctr_opportunity"]) if breakdown["ctr_opportunity"] >= 8
        rows << opportunity("rank_improvement", "順位改善", "検索意図に合わせて本文を更新する", breakdown["seo_opportunity"], reasons["seo_opportunity"]) if breakdown["seo_opportunity"] >= 10
        rows << opportunity("internal_link_addition", "内部リンク追加", "関連記事・店舗ページへの内部リンクを追加する", breakdown["content_opportunity"], reasons["content_opportunity"]) if internal_link_gap?(payload)
        rows << opportunity("shop_addition", "店舗追加", "記事テーマに合う掲載店舗を追加する", breakdown["content_opportunity"], reasons["content_opportunity"]) if shop_gap?(payload)
        rows << opportunity("verified_shop_addition", "確認済店舗追加", "未確認店舗の喫煙情報を確認する", breakdown["content_opportunity"], reasons["content_opportunity"]) if verified_shop_gap?(payload)
        rows << opportunity("content_update", "本文更新", "本文量と最新性を補強する", breakdown["content_opportunity"], reasons["content_opportunity"]) if content_gap?(payload)
        rows << opportunity("cta_improvement", "送客CTA改善", "店舗送客CTAを見直す", breakdown["click_opportunity"], reasons["click_opportunity"]) if breakdown["click_opportunity"] >= 6
        rows.presence || [ opportunity("monitoring", "継続観測", "現状の実績を継続観測する", 0) ]
      end

      def opportunity(type, label, next_action, score, reason = nil)
        {
          "opportunity_type" => type,
          "label" => label,
          "next_action" => next_action,
          "score" => score.to_f.round(1),
          "reason" => reason
        }
      end

      def candidate_draft(snapshot, payload, opportunity, score, breakdown)
        title = "#{article_title(payload)}の#{opportunity['label']}を行う"
        CandidateDraft.new(
          title:,
          action_type: action_type_for(opportunity),
          description: "#{payload['normalized_path']} のArticleAnalyticsSnapshotから #{opportunity['label']} Opportunity を検出しました。",
          execution_prompt: opportunity["next_action"],
          metadata: analysis_metadata(snapshot, payload, score, opportunity["search_demand_score"], opportunity["improvement_potential_score"], opportunity["expected_improvement_score"], breakdown, [ opportunity ]).merge(
            "opportunity_type" => opportunity["opportunity_type"],
            "opportunity_label" => opportunity["label"],
            "next_action" => opportunity["next_action"],
            "opportunity_score_component" => opportunity["score"],
            "search_demand_score" => opportunity["search_demand_score"],
            "improvement_potential_score" => opportunity["improvement_potential_score"],
            "expected_improvement_score" => opportunity["expected_improvement_score"],
            "success_probability" => opportunity["success_probability"],
            "estimated_work_hours" => opportunity["estimated_work_hours"],
            "business_value" => opportunity["business_value"],
            "ranking_reason" => opportunity["ranking_reason"]
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

      def analysis_metadata(snapshot, payload, score, search_demand_score, improvement_potential_score, expected_improvement_score, breakdown, opportunities)
        {
          "value_model_name" => MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => snapshot.id,
          "article_id" => payload["article_id"],
          "article_path" => payload["normalized_path"],
          "opportunity_score" => score,
          "search_demand_score" => search_demand_score.to_f.round(2),
          "improvement_potential_score" => improvement_potential_score.to_f.round(2),
          "expected_improvement_score" => expected_improvement_score.to_f.round(2),
          "success_probability" => primary_metric(opportunities, "success_probability"),
          "estimated_work_hours" => primary_metric(opportunities, "estimated_work_hours"),
          "business_value" => primary_metric(opportunities, "business_value"),
          "score_breakdown" => breakdown,
          "total_score" => score,
          "score_reasons" => score_reasons(payload),
          "score_diagnostics" => {
            "seo_reason" => seo_reason(payload),
            "ctr_reason" => ctr_reason(payload),
            "business_relative" => relative_metrics_for(payload),
            "search_demand_breakdown" => search_demand_breakdown(payload),
            "improvement_potential_breakdown" => {
              "seo" => breakdown["seo_opportunity"],
              "ctr" => breakdown["ctr_opportunity"],
              "pv" => breakdown["pv_opportunity"],
              "click" => breakdown["click_opportunity"],
              "content" => breakdown["content_opportunity"],
              "learning" => breakdown["learning_confidence"]
            }
          },
          "opportunities" => opportunities,
          "ranking_reason" => ranking_reason(payload, score, search_demand_score, improvement_potential_score, expected_improvement_score, breakdown, opportunities),
          "evidence" => evidence(payload),
          "expected_profit_yen" => nil,
          "expected_profit_calculated" => false,
          "calculated_at" => Time.current.iso8601
        }
      end

      def evidence(payload)
        {
          "gsc" => gsc_metrics(payload).slice("available", "impressions", "clicks", "ctr", "average_position", "query_count", "top_queries", "rank_delta", "position_delta", "average_position_delta"),
          "ga4" => ga4_metrics(payload).slice("available", "pageviews", "active_users", "sessions", "engagement_seconds", "pageviews_delta", "pv_delta", "pageviews_change"),
          "shop_click" => shop_click_metrics(payload).slice("available", "total_clicks", "article_shop_clicks", "phone_clicks", "map_clicks", "affiliate_clicks"),
          "article" => payload["article"].to_h.slice("title", "word_count", "internal_link_count", "shop_count", "verified_shop_count", "content_source"),
          "learning" => payload["learning"].to_h.slice("improvement_count", "improvement_success_count", "last_improvement_at")
        }
      end

      def score_reasons(payload)
        gsc = gsc_metrics(payload)
        ga4 = ga4_metrics(payload)
        shop_click = shop_click_metrics(payload)
        article = payload["article"].to_h
        learning = payload["learning"].to_h
        impressions = decimal(gsc["impressions"])
        ctr = normalize_rate(gsc["ctr"])
        position = decimal(gsc["average_position"])
        pageviews = decimal(ga4["pageviews"])
        total_clicks = decimal(shop_click["total_clicks"])
        click_rate = pageviews.positive? ? total_clicks / pageviews : 0.to_d
        engagement_per_view = pageviews.positive? ? decimal(ga4["engagement_seconds"]) / pageviews : 0.to_d
        {
          "seo_opportunity" => "順位#{position.to_f.round(1)}位、表示#{impressions.to_i}、CTR#{(ctr * 100).round(2)}%。11〜20位かつ表示が多い記事ほどSEO改善余地を高く評価。",
          "ctr_opportunity" => "CTR改善見込みクリック=#{(impressions * [ target_ctr(position) - ctr, 0.to_d ].max).round(1)}。表示が少ない記事はCTRが低くても加点を抑制。",
          "pv_opportunity" => "PV=#{pageviews.to_i}、1PVあたりengagement=#{engagement_per_view.round(1)}秒。PVがあり、滞在や推移に改善余地がある場合のみ加点。",
          "click_opportunity" => "ShopClick率=#{(click_rate * 100).round(2)}%。PVに対して送客率が低いほど改善余地を評価。",
          "content_opportunity" => "文字数=#{article['word_count'] || '-'}、内部リンク=#{article['internal_link_count'] || '-'}、店舗数=#{article['shop_count'] || '-'}、確認済=#{article['verified_shop_count'] || '-'}。",
          "learning_confidence" => "改善回数=#{learning['improvement_count'].to_i}、成功回数=#{learning['improvement_success_count'].to_i}、直近改善=#{learning['last_improvement_at'].presence || '-'}。"
        }
      end

      def ranking_reason(payload, score, search_demand_score, improvement_potential_score, expected_improvement_score, breakdown, opportunities)
        primary = primary_opportunity(opportunities)
        main = breakdown.except("learning_confidence").max_by { |_key, value| value.to_d }
        reason = primary&.dig("ranking_reason").presence || score_reasons(payload)[main&.first].presence || "Snapshotから改善余地を評価。"
        "#{primary&.dig('label') || main&.first || 'Opportunity'} が最優先。expected_improvement_score=#{expected_improvement_score.to_f.round(2)}、search_demand_score=#{search_demand_score.to_f.round(2)}、improvement_potential_score=#{improvement_potential_score.to_f.round(2)}、opportunity_score=#{score}。#{reason}"
      end

      def enrich_opportunity(opportunity, payload, search_demand_score, improvement_potential_score)
        success_probability = success_probability_for(payload, opportunity)
        estimated_work_hours = estimated_work_hours_for(opportunity)
        business_value = business_value_for(opportunity)
        expected_improvement_score = expected_improvement_score_for(search_demand_score, improvement_potential_score, success_probability, business_value, estimated_work_hours)

        opportunity.merge(
          "search_demand_score" => search_demand_score.to_f.round(2),
          "improvement_potential_score" => improvement_potential_score.to_f.round(2),
          "success_probability" => success_probability.to_f.round(2),
          "estimated_work_hours" => estimated_work_hours.to_f.round(2),
          "business_value" => business_value.to_f.round(2),
          "expected_improvement_score" => expected_improvement_score.to_f.round(2),
          "ranking_reason" => expected_improvement_reason(opportunity, payload, search_demand_score, improvement_potential_score, success_probability, business_value, estimated_work_hours, expected_improvement_score)
        )
      end

      def expected_improvement_score_for(search_demand_score, improvement_potential_score, success_probability, business_value, estimated_work_hours)
        work_hours = [ estimated_work_hours.to_d, 0.1.to_d ].max
        (search_demand_score.to_d * improvement_potential_score.to_d * success_probability.to_d * business_value.to_d / work_hours).round(2)
      end

      def improvement_potential_score(breakdown)
        seo = decimal(breakdown["seo_opportunity"])
        ctr = decimal(breakdown["ctr_opportunity"])
        pv = decimal(breakdown["pv_opportunity"])
        click = decimal(breakdown["click_opportunity"])
        content = decimal(breakdown["content_opportunity"])
        learning = decimal(breakdown["learning_confidence"])

        weighted = (seo * 1.35) +
          (ctr * 1.45) +
          (pv * 0.9) +
          (click * 1.0) +
          (content * 0.75) +
          (learning * 0.5)
        clamp(weighted, 0, 100).round(2)
      end

      def search_demand_score(payload)
        gsc = gsc_metrics(payload)
        ga4 = ga4_metrics(payload)
        shop_click = shop_click_metrics(payload)
        impressions = decimal(gsc["impressions"])
        query_count = decimal(gsc["query_count"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        pageviews = decimal(ga4["pageviews"])
        active_users = decimal(ga4["active_users"])
        total_clicks = decimal(shop_click["total_clicks"])

        impression_score = clamp(impressions / 3_000, 0, 1)
        query_score = clamp(query_count / 8, 0, 1)
        rank_score = rank_demand_component(position)
        ctr_gap_score = target_ctr(position).positive? ? clamp((target_ctr(position) - ctr) / target_ctr(position), 0, 1) : 0.to_d
        pv_score = clamp(pageviews / 1_000, 0, 1)
        active_user_score = clamp(active_users / 500, 0, 1)
        shop_click_score = clamp(total_clicks / 50, 0, 1)

        weighted = (impression_score * 0.35) +
          (rank_score * 0.2) +
          (ctr_gap_score * 0.15) +
          (query_score * 0.1) +
          (pv_score * 0.1) +
          (active_user_score * 0.05) +
          (shop_click_score * 0.05)
        score = 0.2.to_d + (weighted * 1.8)
        score *= 0.45 if impressions < 100 && pageviews < 100
        score *= 0.6 if position > 50 || position.zero?
        clamp(score, 0.05, 2.0).round(2)
      end

      def success_probability_for(payload, opportunity)
        learning = payload["learning"].to_h
        improvements = decimal(learning["improvement_count"])
        successes = decimal(learning["improvement_success_count"])
        failures = decimal(first_present(learning["improvement_failure_count"], improvements - successes))
        last_improvement_at = parse_time(learning["last_improvement_at"])
        similar_success_rate = normalize_rate(first_present(learning["similar_improvement_success_rate"], learning["similar_success_rate"]))

        base = if similar_success_rate.positive?
                 similar_success_rate
               elsif improvements.positive?
                 successes / [ improvements, 1.to_d ].max
               else
                 0.55.to_d
               end
        base = (base * 0.9) if failures.positive? && failures >= successes
        base = (base * 0.85) if last_improvement_at && last_improvement_at > 30.days.ago
        base = [ base, 0.45.to_d ].max if improvements.zero? && similar_success_rate.zero?
        base = 0.25.to_d if opportunity["opportunity_type"].to_s == "monitoring"
        clamp(base, 0.2, 0.9)
      end

      def estimated_work_hours_for(opportunity)
        case opportunity["opportunity_type"].to_s
        when "ctr_improvement"
          0.3.to_d
        when "internal_link_addition", "verified_shop_addition"
          0.5.to_d
        when "cta_improvement"
          0.8.to_d
        when "shop_addition"
          1.0.to_d
        when "rank_improvement", "content_update"
          1.5.to_d
        when "monitoring"
          0.2.to_d
        else
          1.0.to_d
        end
      end

      def business_value_for(opportunity)
        case opportunity["opportunity_type"].to_s
        when "cta_improvement"
          1.45.to_d
        when "ctr_improvement"
          1.3.to_d
        when "rank_improvement"
          1.2.to_d
        when "shop_addition"
          1.15.to_d
        when "verified_shop_addition"
          1.1.to_d
        when "internal_link_addition"
          1.0.to_d
        when "content_update"
          0.9.to_d
        when "monitoring"
          0.1.to_d
        else
          1.0.to_d
        end
      end

      def expected_improvement_reason(opportunity, payload, search_demand_score, improvement_potential_score, success_probability, business_value, estimated_work_hours, expected_improvement_score)
        base_reason = opportunity["reason"].to_s.presence || "Snapshotから改善余地を検出。"
        demand_reason = search_demand_reason(payload, search_demand_score)
        potential_reason = "改善余地#{improvement_potential_score.to_f.round(2)}。SEO/CTR/PV/送客/本文/Learningの複合で評価。"
        work_reason = if estimated_work_hours <= 0.5.to_d
                        "短時間で実行できるため優先度を上げています。"
                      elsif estimated_work_hours >= 1.5.to_d
                        "作業時間が長いため順位を抑えています。"
                      else
                        "標準的な作業時間として評価しています。"
                      end
        "#{base_reason} #{demand_reason} #{potential_reason} 成功率#{(success_probability * 100).round}%、事業価値係数#{business_value.to_f.round(2)}、推定#{estimated_work_hours.to_f.round(1)}時間で、今やる価値#{expected_improvement_score.to_f.round(2)}。#{work_reason}"
      end

      def search_demand_reason(payload, search_demand_score)
        gsc = gsc_metrics(payload)
        ga4 = ga4_metrics(payload)
        shop_click = shop_click_metrics(payload)
        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        pageviews = decimal(ga4["pageviews"])
        total_clicks = decimal(shop_click["total_clicks"])

        if impressions >= 1_000 && position >= 11 && position <= 20 && target_ctr(position) > ctr
          "表示回数#{impressions.to_i}・順位#{position.to_f.round(1)}位・CTR#{(ctr * 100).round(2)}%のため改善インパクトが非常に高い。"
        elsif search_demand_score < 0.5.to_d
          "検索需要が小さいため内部リンク改善だけでは優先度を抑制。"
        else
          "検索需要係数#{search_demand_score.to_f.round(2)}。PV#{pageviews.to_i}、ShopClick#{total_clicks.to_i}も加味。"
        end
      end

      def primary_opportunity(opportunities)
        Array(opportunities).max_by { |opportunity| decimal(opportunity["expected_improvement_score"]) }
      end

      def primary_metric(opportunities, key)
        primary_opportunity(opportunities)&.dig(key)
      end

      def gsc_metrics(payload)
        gsc = payload["gsc"].to_h
        impressions = first_present(gsc["impressions"], gsc["表示回数"])
        clicks = first_present(gsc["clicks"], gsc["クリック数"])
        ctr = first_present(gsc["ctr"], gsc["current_ctr"], gsc["CTR"])
        position = first_present(gsc["average_position"], gsc["position"], gsc["avg_position"], gsc["掲載順位"], gsc["平均掲載順位"])
        {
          "available" => truthy?(gsc["available"]) || [ impressions, clicks, ctr, position ].any?(&:present?),
          "impressions" => impressions,
          "clicks" => clicks,
          "ctr" => ctr,
          "average_position" => position,
          "query_count" => first_present(gsc["query_count"], gsc["queries_count"], Array(gsc["top_queries"]).size),
          "top_queries" => gsc["top_queries"],
          "rank_delta" => first_present(gsc["rank_delta"], gsc["position_delta"], gsc["average_position_delta"]),
          "position_delta" => gsc["position_delta"],
          "average_position_delta" => gsc["average_position_delta"]
        }
      end

      def ga4_metrics(payload)
        ga4 = payload["ga4"].to_h
        pageviews = first_present(ga4["pageviews"], ga4["views"], ga4["screenPageViews"])
        active_users = first_present(ga4["active_users"], ga4["activeUsers"], ga4["users"])
        sessions = ga4["sessions"]
        engagement_seconds = first_present(ga4["engagement_seconds"], ga4["userEngagementDuration"])
        {
          "available" => truthy?(ga4["available"]) || [ pageviews, active_users, sessions, engagement_seconds ].any?(&:present?),
          "pageviews" => pageviews,
          "active_users" => active_users,
          "sessions" => sessions,
          "engagement_seconds" => engagement_seconds,
          "pageviews_delta" => first_present(ga4["pageviews_delta"], ga4["pv_delta"], ga4["pageviews_change"]),
          "pv_delta" => ga4["pv_delta"],
          "pageviews_change" => ga4["pageviews_change"]
        }
      end

      def shop_click_metrics(payload)
        shop_click = payload["shop_click"].to_h
        phone = decimal(shop_click["phone_clicks"])
        map = decimal(shop_click["map_clicks"])
        affiliate = decimal(shop_click["affiliate_clicks"])
        article_shop = decimal(shop_click["article_shop_clicks"])
        total = first_present(shop_click["total_clicks"], phone + map + affiliate + article_shop)
        {
          "available" => truthy?(shop_click["available"]) || decimal(total).positive?,
          "total_clicks" => total,
          "article_shop_clicks" => shop_click["article_shop_clicks"],
          "phone_clicks" => shop_click["phone_clicks"],
          "map_clicks" => shop_click["map_clicks"],
          "affiliate_clicks" => shop_click["affiliate_clicks"]
        }
      end

      def seo_reason(payload)
        gsc = gsc_metrics(payload)
        return "GSC unavailable" unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        relative = relative_metrics_for(payload)
        return "表示0のためSEO改善対象外" if impressions.zero?
        return "average_position nil" if position.zero?
        return "順位50位以降で改善確度が低い" if position > 50
        return "Business内表示上位#{relative['impression_percentile_label']}・順位11〜20・CTR平均との差あり" if position >= 11 && position <= 20 && relative["impressions_at_or_above_median"] && relative["ctr_gap_to_business"].to_d.positive?
        return "Business内表示上位#{relative['impression_percentile_label']}・順位11〜20のためSEO改善余地あり" if position >= 11 && position <= 20 && relative["impressions_at_or_above_median"]
        return "Business内表示下位のため優先度低" unless relative["impressions_in_top_30_percent"] || relative["impressions_at_or_above_median"]
        return "CTRはBusiness平均以上だが順位改善余地あり" unless relative["ctr_gap_to_business"].to_d.positive?

        "Business内表示上位#{relative['impression_percentile_label']}・CTR#{(ctr * 100).round(2)}%で改善余地あり"
      end

      def ctr_reason(payload)
        gsc = gsc_metrics(payload)
        return "GSC unavailable" unless gsc["available"]

        impressions = decimal(gsc["impressions"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        relative = relative_metrics_for(payload)
        return "表示0のためCTR改善対象外" if impressions.zero?
        return "average_position nil" if position.zero?
        return "順位50位以降でCTR改善確度が低い" if position > 50
        return "Business内表示下位のためCTR改善優先度低" unless relative["impressions_in_top_30_percent"] || relative["impressions_at_or_above_median"]
        return "CTRはBusiness平均以上" unless relative["ctr_gap_to_business"].to_d.positive?

        "Business内表示上位#{relative['impression_percentile_label']}・CTR#{(ctr * 100).round(2)}%でBusiness平均との差あり"
      end

      def search_demand_breakdown(payload)
        gsc = gsc_metrics(payload)
        ga4 = ga4_metrics(payload)
        shop_click = shop_click_metrics(payload)
        impressions = decimal(gsc["impressions"])
        query_count = decimal(gsc["query_count"])
        position = decimal(gsc["average_position"])
        ctr = normalize_rate(gsc["ctr"])
        pageviews = decimal(ga4["pageviews"])
        active_users = decimal(ga4["active_users"])
        total_clicks = decimal(shop_click["total_clicks"])

        {
          "impression" => clamp(impressions / 3_000, 0, 1).to_f.round(2),
          "query" => clamp(query_count / 8, 0, 1).to_f.round(2),
          "rank" => rank_demand_component(position).to_f.round(2),
          "ctr_gap" => (target_ctr(position).positive? ? clamp((target_ctr(position) - ctr) / target_ctr(position), 0, 1) : 0.to_d).to_f.round(2),
          "pv" => clamp(pageviews / 1_000, 0, 1).to_f.round(2),
          "active" => clamp(active_users / 500, 0, 1).to_f.round(2),
          "shop_click" => clamp(total_clicks / 50, 0, 1).to_f.round(2)
        }
      end

      def rank_demand_component(position)
        if position >= 11 && position <= 20
          1.to_d
        elsif position > 5 && position <= 10
          0.65.to_d
        elsif position > 20 && position <= 30
          0.55.to_d
        elsif position > 30 && position <= 50
          0.25.to_d
        elsif position.positive?
          0.08.to_d
        else
          0.to_d
        end
      end

      def truthy?(value)
        value == true || value.to_s == "true" || value.to_s == "1"
      end

      def business_statistics
        @business_statistics ||= begin
          rows = snapshots.map do |snapshot|
            payload = snapshot.payload.to_h.deep_stringify_keys
            gsc = gsc_metrics(payload)
            ga4 = ga4_metrics(payload)
            shop_click = shop_click_metrics(payload)
            impressions = decimal(gsc["impressions"])
            position = decimal(gsc["average_position"])
            ctr = normalize_rate(gsc["ctr"])
            {
              "article_key" => article_key(payload),
              "impressions" => impressions,
              "ctr" => ctr,
              "position" => position,
              "pageviews" => decimal(ga4["pageviews"]),
              "shop_clicks" => decimal(shop_click["total_clicks"]),
              "search_demand_metric" => impressions * rank_demand_component(position)
            }
          end
          impression_values = rows.map { |row| row["impressions"] }.select(&:positive?)
          ctr_values = rows.map { |row| row["ctr"] }.select(&:positive?)
          position_values = rows.map { |row| row["position"] }.select(&:positive?)
          {
            "article_count" => rows.size,
            "impressions_median" => median(impression_values).to_f.round(2),
            "impressions_average" => average(impression_values).to_f.round(2),
            "impressions_top_20_percent_threshold" => percentile_threshold(impression_values, 0.8).to_f.round(2),
            "impressions_top_30_percent_threshold" => percentile_threshold(impression_values, 0.7).to_f.round(2),
            "ctr_median" => median(ctr_values).to_f.round(4),
            "ctr_average" => average(ctr_values).to_f.round(4),
            "position_median" => median(position_values).to_f.round(2),
            "position_average" => average(position_values).to_f.round(2),
            "impression_ranks" => rank_map(rows, "impressions", :desc),
            "ctr_low_ranks" => rank_map(rows, "ctr", :asc),
            "search_demand_ranks" => rank_map(rows, "search_demand_metric", :desc)
          }
        end
      end

      def relative_metrics_for(payload)
        stats = business_statistics
        gsc = gsc_metrics(payload)
        key = article_key(payload)
        total = [ stats["article_count"].to_i, 1 ].max
        impressions = decimal(gsc["impressions"])
        ctr = normalize_rate(gsc["ctr"])
        impression_rank = stats.dig("impression_ranks", key).to_i
        ctr_rank = stats.dig("ctr_low_ranks", key).to_i
        search_demand_rank = stats.dig("search_demand_ranks", key).to_i
        impression_percentile = rank_percentile(impression_rank, total)
        ctr_low_percentile = rank_percentile(ctr_rank, total)
        ctr_benchmark = [ decimal(stats["ctr_median"]), decimal(stats["ctr_average"]) ].max

        {
          "article_count" => total,
          "business_impressions_median" => stats["impressions_median"],
          "business_impressions_average" => stats["impressions_average"],
          "business_ctr_median" => stats["ctr_median"],
          "business_ctr_average" => stats["ctr_average"],
          "business_position_median" => stats["position_median"],
          "business_position_average" => stats["position_average"],
          "impression_rank" => impression_rank.positive? ? impression_rank : nil,
          "ctr_rank" => ctr_rank.positive? ? ctr_rank : nil,
          "search_demand_rank" => search_demand_rank.positive? ? search_demand_rank : nil,
          "impression_percentile" => impression_percentile.to_f.round(2),
          "ctr_low_percentile" => ctr_low_percentile.to_f.round(2),
          "impression_percentile_label" => "#{(impression_percentile * 100).round}%",
          "impressions_in_top_20_percent" => rank_within_percent?(impression_rank, total, 0.2),
          "impressions_in_top_30_percent" => rank_within_percent?(impression_rank, total, 0.3),
          "impressions_at_or_above_median" => impressions.positive? && impressions >= decimal(stats["impressions_median"]),
          "ctr_below_business_average" => ctr_benchmark.positive? && ctr < ctr_benchmark,
          "ctr_gap_to_business" => ctr_benchmark.positive? ? clamp((ctr_benchmark - ctr) / ctr_benchmark, 0, 1).to_f.round(2) : 0
        }
      end

      def article_key(payload)
        first_present(payload["article_id"], payload["normalized_path"], payload["slug"]).to_s
      end

      def rank_map(rows, key, direction)
        sorted = rows.sort_by { |row| decimal(row[key]) }
        sorted.reverse! if direction == :desc
        sorted.each_with_index.to_h { |row, index| [ row["article_key"], index + 1 ] }
      end

      def rank_percentile(rank, total)
        return 0.to_d unless rank.to_i.positive?
        return 1.to_d if total.to_i <= 1

        clamp(1.to_d - ((rank.to_d - 1) / (total.to_d - 1)), 0, 1)
      end

      def rank_within_percent?(rank, total, percent)
        return false unless rank.to_i.positive?

        rank.to_i <= [(total.to_d * percent.to_d).ceil, 1].max
      end

      def median(values)
        sorted = values.map(&:to_d).sort
        return 0.to_d if sorted.empty?

        mid = sorted.length / 2
        sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
      end

      def average(values)
        rows = values.map(&:to_d)
        return 0.to_d if rows.empty?

        rows.sum / rows.size
      end

      def percentile_threshold(values, percentile)
        sorted = values.map(&:to_d).sort
        return 0.to_d if sorted.empty?

        index = ((sorted.size - 1) * percentile.to_d).ceil
        sorted[index]
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

      def normalize_rate(value)
        rate = decimal(value)
        rate > 1 ? rate / 100 : rate
      end

      def first_present(*values)
        values.find { |value| value.present? }
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      def clamp(value, min, max)
        [[ value.to_d, min.to_d ].max, max.to_d ].min
      end
    end
  end
end
