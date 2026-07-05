module Aicoo
  module UniversalAnalysisEngine
    class OpportunityPatternDetector
      Issue = Aicoo::BusinessAnalyzers::BaseAnalyzer::Issue

      PATTERNS = %w[
        demand_without_supply
        high_impression_low_ctr
        near_win_position
        high_traffic_low_conversion
        asset_missing
        weak_existing_asset
        supply_gap
        verification_gap
        engagement_signal
        funnel_drop
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(business:, signals:, today: Date.current)
        @business = business
        @signals = signals
        @today = today.to_date
        @profile = Aicoo::BusinessCapabilityProfile.for(business)
      end

      def call
        signals.flat_map { |signal| issues_for(signal) }.compact
      end

      private

      attr_reader :business, :signals, :today, :profile

      def issues_for(signal)
        [
          demand_without_supply(signal),
          high_impression_low_ctr(signal),
          near_win_position(signal),
          high_traffic_low_conversion(signal),
          asset_missing(signal),
          weak_existing_asset(signal),
          supply_gap(signal),
          verification_gap(signal),
          engagement_signal(signal),
          funnel_drop(signal)
        ].compact
      end

      def demand_without_supply(signal)
        return unless signal.demand_score.to_d >= 120
        return unless signal.supply_score.to_d < 25

        issue_for(signal, "demand_without_supply", "#{target(signal)}の供給不足を解消する", "需要がある一方で対応資産または供給量が不足しています。", 20, "件", "需要スコア#{signal.demand_score.round(1)}に対して供給スコア#{signal.supply_score.round(1)}です。")
      end

      def high_impression_low_ctr(signal)
        return unless signal.impressions.to_i >= 100
        return unless signal.ctr.to_d < 0.02.to_d

        issue_for(signal, "high_impression_low_ctr", "#{target(signal)}のCTRを改善する", "表示回数に対してクリック率が低い状態です。", 3, "件", "impressions=#{signal.impressions}, CTR=#{percent(signal.ctr)}で、目標CTR3%を下回っています。")
      end

      def near_win_position(signal)
        return unless signal.position.to_d.between?(8, 20)

        issue_for(signal, "near_win_position", "#{target(signal)}の上位化余地を補強する", "検索順位が8〜20位で、少量の補強で上位化できる可能性があります。", 1, "ページ", "平均順位#{signal.position.round(1)}位で、内部リンク・冒頭改善・FAQ追加の余地があります。")
      end

      def high_traffic_low_conversion(signal)
        return unless signal.clicks.to_i + signal.sessions.to_i + signal.pageviews.to_i >= 50
        return unless signal.conversion_events.to_i + signal.conversions.to_i <= 0

        issue_for(signal, "high_traffic_low_conversion", "#{target(signal)}のCV導線を増やす", "流入はあるのにCVに近いイベントが発生していません。", 5, "ページ", "traffic=#{signal.clicks.to_i + signal.sessions.to_i + signal.pageviews.to_i}に対してCVイベント0です。")
      end

      def asset_missing(signal)
        return unless signal.asset_match_score.to_d < 0.3.to_d
        return unless signal.demand_score.to_d >= 80

        issue_for(signal, "asset_missing", "#{target(signal)}の対応資産を作る", "需要に対応する既存資産が見つかりません。", 1, "件", "asset_match_score=#{signal.asset_match_score.round(2)}で、対応ページ・記事・LPなどが不足しています。")
      end

      def weak_existing_asset(signal)
        return unless signal.asset_match_score.to_d >= 0.3.to_d
        return unless signal.ctr.to_d < 0.025.to_d || signal.ga4_engagement_score.to_d < 20.to_d

        issue_for(signal, "weak_existing_asset", "#{target(signal)}の既存資産を改善する", "対応資産はありますが、CTRまたはエンゲージメントが弱い状態です。", 1, "件", "asset_match_score=#{signal.asset_match_score.round(2)}, CTR=#{percent(signal.ctr)}, engagement=#{signal.ga4_engagement_score.round(1)}です。")
      end

      def supply_gap(signal)
        return unless profile.supply_assets.any?
        return unless signal.demand_score.to_d >= 80
        return unless signal.supply_score.to_d < 40

        issue_for(signal, "supply_gap", "#{target(signal)}の供給資産を増やす", "需要に対して供給資産が少ない状態です。", 20, "件", "Businessの供給資産#{profile.supply_assets.join('/')}に対して需要が上回っています。")
      end

      def verification_gap(signal)
        return unless profile.quality_assets.any?
        return unless signal.supply_score.to_d.positive?
        return unless signal.conversion_intent_score.to_d >= 1.1.to_d

        issue_for(signal, "verification_gap", "#{target(signal)}の品質確認を進める", "CV意図がある需要に対して品質確認済み資産を増やす余地があります。", 15, "件", "品質資産#{profile.quality_assets.join('/')}がCV意図のある入口で重要です。")
      end

      def engagement_signal(signal)
        return unless signal.pageviews.to_i + signal.sessions.to_i >= 30
        return unless signal.ga4_engagement_score.to_d < 20.to_d

        issue_for(signal, "engagement_signal", "#{target(signal)}の回遊を改善する", "流入後のエンゲージメントが弱い状態です。", 3, "件", "GA4 engagement_score=#{signal.ga4_engagement_score.round(1)}で、関連導線・内部リンクを補強する余地があります。")
      end

      def funnel_drop(signal)
        return unless signal.pageviews.to_i >= 50
        return unless signal.conversion_events.to_i <= 0

        issue_for(signal, "funnel_drop", "#{target(signal)}のファネル離脱を減らす", "ページ閲覧からCV行動に進んでいません。", 5, "ページ", "pageviews=#{signal.pageviews}, conversion_events=#{signal.conversion_events}です。")
      end

      def issue_for(signal, pattern, title, description, quantity, unit, why)
        Issue.new(
          key: pattern,
          title:,
          description:,
          action_type: action_type_for(pattern),
          quantity:,
          unit:,
          why:,
          expected_effect: expected_effect_for(pattern, signal),
          expected_value_yen: [ signal.expected_value_yen.to_i, 6_000 ].max,
          success_probability: success_probability_for(pattern),
          strategic_value_score: strategic_value_for(pattern),
          risk_reduction_score: risk_reduction_for(pattern),
          expected_hours: [ signal.work_cost.to_d, 0.4.to_d ].max,
          confidence_score: confidence_for(signal),
          metadata: metadata_for(signal, pattern)
        )
      end

      def metadata_for(signal, pattern)
        {
          "opportunity_type" => pattern,
          "target_type" => signal.target_type,
          "target_identifier" => signal.target_label,
          "target_url_or_identifier" => signal.page_path.presence || signal.query.presence || signal.target_label,
          "source_query" => signal.query,
          "page_path" => signal.page_path,
          "current_value" => current_value_for(pattern, signal),
          "benchmark_value" => benchmark_value_for(pattern),
          "source_metric" => pattern,
          "evidence_sources" => signal.metadata.to_h["evidence_sources"],
          "supporting_signal" => signal.to_h,
          "business_capabilities" => profile.to_h,
          "codex_eligible" => %w[high_traffic_low_conversion funnel_drop data_quality_gap].include?(pattern),
          "candidate_pages" => [ signal.page_path, signal.target_label ].compact_blank
        }.compact
      end

      def target(signal)
        signal.query.presence || signal.page_path.presence || signal.target_label
      end

      def action_type_for(pattern)
        {
          "high_traffic_low_conversion" => "ui_improvement",
          "funnel_drop" => "ui_improvement",
          "high_impression_low_ctr" => "seo_improvement",
          "near_win_position" => "seo_improvement",
          "weak_existing_asset" => "seo_improvement",
          "engagement_signal" => "seo_improvement",
          "demand_without_supply" => "data_preparation",
          "supply_gap" => "data_preparation",
          "verification_gap" => "data_preparation",
          "asset_missing" => "seo_article"
        }.fetch(pattern, "other")
      end

      def expected_effect_for(pattern, signal)
        case pattern
        when "high_impression_low_ctr" then "CTR +0.8pt、月間クリック +#{[ signal.impressions.to_i / 20, 10 ].max}"
        when "near_win_position" then "平均順位 +2位、クリック増加"
        when "high_traffic_low_conversion", "funnel_drop" then "CVイベント +#{[ signal.pageviews.to_i / 50, 2 ].max}/週"
        when "verification_gap" then "品質確認済み資産 +15件、CVR改善"
        else "期待利益 +#{signal.expected_value_yen.to_i}円"
        end
      end

      def current_value_for(pattern, signal)
        case pattern
        when "high_impression_low_ctr" then signal.ctr
        when "near_win_position" then signal.position
        when "high_traffic_low_conversion", "funnel_drop" then signal.conversion_events
        when "engagement_signal" then signal.ga4_engagement_score
        else signal.supply_score
        end
      end

      def benchmark_value_for(pattern)
        {
          "high_impression_low_ctr" => 0.03,
          "near_win_position" => 10,
          "high_traffic_low_conversion" => 1,
          "funnel_drop" => 1,
          "engagement_signal" => 25
        }.fetch(pattern, 1)
      end

      def success_probability_for(pattern)
        {
          "high_impression_low_ctr" => 0.42,
          "near_win_position" => 0.36,
          "high_traffic_low_conversion" => 0.4,
          "funnel_drop" => 0.38,
          "supply_gap" => 0.52,
          "verification_gap" => 0.5
        }.fetch(pattern, 0.38)
      end

      def strategic_value_for(pattern)
        %w[demand_without_supply asset_missing supply_gap].include?(pattern) ? 66 : 54
      end

      def risk_reduction_for(pattern)
        %w[data_quality_gap verification_gap].include?(pattern) ? 50 : 28
      end

      def confidence_for(signal)
        days = signal.metadata.to_h["recent_metric_days"].to_i
        return 32 if days <= 2
        return 42 if days <= 6
        return 52 if days <= 14

        62
      end

      def percent(value)
        "#{(value.to_d * 100).round(1)}%"
      end
    end
  end
end
