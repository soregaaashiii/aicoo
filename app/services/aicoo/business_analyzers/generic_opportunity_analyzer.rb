module Aicoo
  module BusinessAnalyzers
    class GenericOpportunityAnalyzer < BaseAnalyzer
      MIN_DEMAND_IMPRESSIONS = 100
      LOW_CTR_THRESHOLD = 0.02.to_d
      LOW_CONVERSION_THRESHOLD = 1

      private

      def handled_business_type?
        true
      end

      def issues
        [
          data_quality_gap_issue,
          demand_without_asset_issue,
          high_impression_low_ctr_issue,
          rank_11_20_gap_issue,
          traffic_without_conversion_issue,
          asset_without_traffic_issue,
          activity_gap_issue
        ].compact
      end

      def data_quality_gap_issue
        return if recent_metrics.any? && conversion_measurement_present?

        missing = []
        missing << "GA4/GSC日次指標" if recent_metrics.empty?
        missing << "CVイベント計測" unless conversion_measurement_present?
        target = missing.first || "計測設定"

        issue(
          key: "data_quality_gap",
          title: "#{target}を確認して成果判断できる状態にする",
          description: "#{business.name}で改善判断に必要なデータが不足しています。",
          action_type: "data_preparation",
          quantity: missing.size.clamp(1, 3),
          unit: "項目",
          why: "#{missing.join(' / ')} が不足しており、次の改善判断の精度が落ちています。",
          expected_effect: "改善候補の信頼度 +20pt",
          expected_value_yen: estimated_value(8_000),
          success_probability: 0.72,
          strategic_value_score: 42,
          risk_reduction_score: 60,
          expected_hours: 0.5,
          metadata: common_metadata(
            "data_quality_gap",
            target_type: "measurement",
            target_identifier: target,
            current_value: recent_metrics.size,
            benchmark_value: 7,
            source_metric: "measurement_readiness",
            required_resources: { "missing" => missing },
            concrete_task: "#{target}を確認する"
          )
        )
      end

      def demand_without_asset_issue
        query = demand_query
        return if query.blank?
        return if asset_exists_for?(query)

        task = task_for_missing_asset(query)
        issue(
          key: "demand_without_asset",
          title: task.fetch(:title),
          description: "#{query} の需要がありますが、対応する#{task.fetch(:asset_label)}が見つかりません。",
          action_type: task.fetch(:action_type),
          quantity: 1,
          unit: task.fetch(:unit),
          why: "SERP/GSCに需要シグナルがありますが、Businessの対応資産が不足しています。",
          expected_effect: "新規入口 1件、初月クリック +20",
          expected_value_yen: estimated_value(24_000),
          success_probability: 0.38,
          strategic_value_score: 68,
          risk_reduction_score: 24,
          expected_hours: task.fetch(:hours),
          metadata: common_metadata(
            "demand_without_asset",
            target_type: task.fetch(:target_type),
            target_identifier: query,
            query:,
            current_value: 0,
            benchmark_value: 1,
            source_metric: "serp_or_gsc_demand",
            concrete_task: task.fetch(:title),
            required_resources: task
          )
        )
      end

      def high_impression_low_ctr_issue
        return if recent_impressions < MIN_DEMAND_IMPRESSIONS
        return unless recent_ctr < LOW_CTR_THRESHOLD

        query = demand_query.presence || "流入上位検索入口"
        amount = [ (recent_impressions / 500.0).ceil, 3 ].max.clamp(1, 8)
        issue(
          key: "high_impression_low_ctr",
          title: "#{query}のCTRを#{amount}件改善する",
          description: "表示回数はありますがCTRが低く、検索結果またはファーストビューでクリック理由が弱い状態です。",
          action_type: "seo_improvement",
          quantity: amount,
          unit: "件",
          why: "直近7日のimpressions=#{recent_impressions}, clicks=#{recent_clicks}, CTR=#{percent(recent_ctr)}です。",
          expected_effect: "CTR +0.8pt、月間クリック +#{[ amount * 12, 20 ].max}",
          expected_value_yen: estimated_value(22_000),
          success_probability: 0.42,
          strategic_value_score: 58,
          risk_reduction_score: 28,
          expected_hours: 1.2,
          metadata: common_metadata(
            "high_impression_low_ctr",
            target_type: "traffic_entry",
            target_identifier: query,
            query:,
            current_value: recent_ctr.to_f,
            benchmark_value: 0.03,
            source_metric: "ctr",
            concrete_task: "#{query}のタイトル・meta・ファーストビュー訴求を#{amount}件改善する"
          )
        )
      end

      def rank_11_20_gap_issue
        position = recent_average_position
        return unless position >= 11 && position <= 20

        query = demand_query.presence || "順位11〜20位の検索入口"
        issue(
          key: "rank_11_20_gap",
          title: "#{query}の不足要素を1ページで補強する",
          description: "検索順位が11〜20位にあり、少量の補強で上位化の余地があります。",
          action_type: "seo_improvement",
          quantity: 1,
          unit: "ページ",
          why: "平均順位が#{position.round(1)}位で、内部リンク・FAQ・比較要素の補強余地があります。",
          expected_effect: "平均順位 +2.0位、CTR +0.6pt",
          expected_value_yen: estimated_value(20_000),
          success_probability: 0.36,
          strategic_value_score: 60,
          risk_reduction_score: 32,
          expected_hours: 1.5,
          metadata: common_metadata(
            "rank_11_20_gap",
            target_type: "page_or_query",
            target_identifier: query,
            query:,
            current_value: position.to_f,
            benchmark_value: 10,
            source_metric: "average_position",
            concrete_task: "#{query}にFAQ・比較要素・内部リンクを追加する"
          )
        )
      end

      def traffic_without_conversion_issue
        return unless recent_traffic.positive?
        return unless recent_conversions_total < LOW_CONVERSION_THRESHOLD

        amount = [ top_page_count, 5 ].max.clamp(3, 10)
        event_label = capability.conversion_events.first || "CV"
        issue(
          key: "traffic_without_conversion",
          title: "流入上位#{amount}ページに#{event_label}導線を追加する",
          description: "流入はありますが、CVに近いイベントが少ない状態です。",
          action_type: "ui_improvement",
          quantity: amount,
          unit: "ページ",
          why: "直近7日のtraffic=#{recent_traffic}に対してconversion_events=#{recent_conversions_total}です。",
          expected_effect: "CVイベント +#{amount * 2}/週",
          expected_value_yen: estimated_value(30_000),
          success_probability: 0.4,
          strategic_value_score: 62,
          risk_reduction_score: 34,
          expected_hours: 2,
          metadata: common_metadata(
            "traffic_without_conversion",
            target_type: "conversion_path",
            target_identifier: "流入上位ページ",
            current_value: recent_conversions_total,
            benchmark_value: 1,
            source_metric: "traffic_to_conversion",
            concrete_task: "流入上位#{amount}ページに#{event_label}導線を追加する",
            required_resources: { "conversion_events" => capability.conversion_events }
          )
        )
      end

      def asset_without_traffic_issue
        return unless recent_asset_activity_count.positive?
        return if recent_traffic.positive?

        target = recent_asset_label
        issue(
          key: "asset_without_traffic",
          title: "#{target}への流入導線を3件追加する",
          description: "資産は作成されていますが、流入がまだありません。",
          action_type: "seo_improvement",
          quantity: 3,
          unit: "件",
          why: "直近30日に#{target}のActivityがありますが、直近7日のtrafficが0です。",
          expected_effect: "初回流入 +15クリック/月",
          expected_value_yen: estimated_value(12_000),
          success_probability: 0.34,
          strategic_value_score: 44,
          risk_reduction_score: 22,
          expected_hours: 1,
          metadata: common_metadata(
            "asset_without_traffic",
            target_type: "asset",
            target_identifier: target,
            current_value: recent_traffic,
            benchmark_value: 1,
            source_metric: "asset_traffic",
            concrete_task: "#{target}へ内部リンク・検索入口・導線を3件追加する"
          )
        )
      end

      def activity_gap_issue
        return if recent_activity_count.positive?

        asset = capability.primary_assets.first || "改善対象"
        issue(
          key: "activity_gap",
          title: "#{asset}の改善作業を1件実行する",
          description: "一定期間、改善Activityがありません。",
          action_type: "operations",
          quantity: 1,
          unit: "件",
          why: "直近30日のBusinessActivityLogが0件です。改善サイクルが止まっています。",
          expected_effect: "学習データ 1件追加、次回判断精度向上",
          expected_value_yen: estimated_value(6_000),
          success_probability: 0.55,
          strategic_value_score: 36,
          risk_reduction_score: 40,
          expected_hours: 0.7,
          metadata: common_metadata(
            "activity_gap",
            target_type: "operation",
            target_identifier: asset,
            current_value: recent_activity_count,
            benchmark_value: 1,
            source_metric: "activity_count",
            concrete_task: "#{asset}の小さな改善を1件実行する"
          )
        )
      end

      def common_metadata(pattern, target_type:, target_identifier:, current_value:, benchmark_value:, source_metric:, concrete_task:, query: nil, required_resources: {})
        {
          "opportunity_type" => pattern,
          "target_type" => target_type,
          "target_identifier" => target_identifier,
          "target_url_or_identifier" => target_identifier,
          "source_query" => query,
          "current_value" => current_value,
          "benchmark_value" => benchmark_value,
          "source_metric" => source_metric,
          "concrete_task" => concrete_task,
          "evidence_sources" => evidence_sources_for(pattern),
          "business_capabilities" => capability.to_h,
          "required_resources" => required_resources,
          "codex_eligible" => codex_eligible_for(pattern),
          "candidate_pages" => candidate_pages_for(target_identifier)
        }.compact
      end

      def capability
        @capability ||= Aicoo::BusinessCapabilityProfile.for(business)
      end

      def recent_metrics
        @recent_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 6)..today).to_a
      end

      def recent30_metrics
        @recent30_metrics ||= business.business_metric_dailies.where(recorded_on: (today - 29)..today).to_a
      end

      def recent_total(metric)
        recent_metrics.sum { |record| record.public_send(metric).to_i }
      end

      def recent_average(metric)
        values = recent_metrics.filter_map { |record| record.public_send(metric).to_d if record.public_send(metric).to_d.positive? }
        return 0.to_d if values.empty?

        values.sum / values.size
      end

      def recent_impressions = recent_total(:impressions)
      def recent_clicks = recent_total(:clicks)
      def recent_sessions = recent_total(:sessions)
      def recent_pageviews = recent_total(:pageviews)
      def recent_conversions = recent_total(:conversions)

      def recent_conversion_clicks
        recent_total(:phone_clicks) + recent_total(:map_clicks) + recent_total(:affiliate_clicks)
      end

      def recent_conversions_total
        recent_conversions + recent_conversion_clicks
      end

      def recent_traffic
        recent_clicks + recent_sessions + recent_pageviews
      end

      def recent_ctr
        return 0.to_d if recent_impressions.zero?

        recent_clicks.to_d / recent_impressions.to_d
      end

      def recent_average_position
        recent_average(:average_position)
      end

      def recent_activity_count
        @recent_activity_count ||= business.business_activity_logs.where(occurred_at: 30.days.ago..Time.current).count
      end

      def recent_asset_activity_count
        @recent_asset_activity_count ||= business.business_activity_logs
                                                 .where(resource_type: asset_resource_types, occurred_at: 30.days.ago..Time.current)
                                                 .count
      end

      def recent_asset_label
        capability.content_assets.first || capability.primary_assets.first || "作成済み資産"
      end

      def asset_resource_types
        types = []
        types << "Article" if capability.has_articles
        types << "LandingPage" if capability.has_lp
        types << "Shop" if capability.has_listings
        types.presence || %w[Article LandingPage Page]
      end

      def conversion_measurement_present?
        recent_conversions_total.positive? || recent_metrics.any? { |record| record.event_count.to_i.positive? }
      end

      def demand_query
        @demand_query ||= business.serp_queries.enabled.by_priority.limit(1).pick(:query).presence ||
          business.serp_analyses.successful.order(analyzed_at: :desc, created_at: :desc).pick(:keyword).presence ||
          gsc_like_query
      end

      def gsc_like_query
        return if recent_impressions < MIN_DEMAND_IMPRESSIONS

        [ business.name, "比較" ].compact_blank.join(" ")
      end

      def asset_exists_for?(query)
        normalized = query.to_s.downcase
        return false if normalized.blank?

        business.business_activity_logs
                .where(resource_type: asset_resource_types, occurred_at: 180.days.ago..Time.current)
                .where("title ILIKE ? OR diff_summary ILIKE ?", "%#{normalized}%", "%#{normalized}%")
                .exists?
      end

      def task_for_missing_asset(query)
        if capability.has_articles
          {
            title: "「#{query}」向けの記事を1本作成する",
            asset_label: "記事",
            action_type: "seo_article",
            target_type: "article",
            unit: "本",
            hours: 1.5
          }
        elsif capability.has_lp
          {
            title: "#{query}に対応するLPセクションを1つ追加する",
            asset_label: "LPセクション",
            action_type: "lp_improvement",
            target_type: "lp_section",
            unit: "セクション",
            hours: 1.2
          }
        else
          {
            title: "#{query}に対応する受け皿ページを1つ作成する",
            asset_label: "受け皿",
            action_type: "asset_creation",
            target_type: "page",
            unit: "件",
            hours: 1.5
          }
        end
      end

      def top_page_count
        [ (recent_pageviews / 100.0).ceil, 3 ].max
      end

      def evidence_sources_for(pattern)
        {
          "demand_without_asset" => %w[gsc serp business_db],
          "high_impression_low_ctr" => %w[gsc ga4],
          "rank_11_20_gap" => %w[gsc serp],
          "traffic_without_conversion" => %w[ga4 business_db],
          "asset_without_traffic" => %w[ga4 activity_log],
          "activity_gap" => %w[activity_log],
          "data_quality_gap" => %w[business_db]
        }.fetch(pattern, %w[business_db])
      end

      def codex_eligible_for(pattern)
        pattern.in?(%w[traffic_without_conversion data_quality_gap])
      end

      def candidate_pages_for(target_identifier)
        [ target_identifier ].compact_blank
      end

      def estimated_value(base)
        multiplier = [ recent30_metrics.size / 7.0, 1 ].max
        (base * multiplier).round
      end

      def percent(value)
        "#{(value.to_d * 100).round(1)}%"
      end

      def issue(**attributes)
        Issue.new(**{ confidence_score: confidence_score }.merge(attributes))
      end

      def confidence_score
        case recent30_metrics.size
        when 0 then 18
        when 1..2 then 24
        when 3..6 then 34
        when 7...14 then 42
        when 14...30 then 52
        else 64
        end
      end
    end
  end
end
