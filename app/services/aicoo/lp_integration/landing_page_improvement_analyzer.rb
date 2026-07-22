require "digest"
require "uri"

module Aicoo
  module LpIntegration
    class LandingPageImprovementAnalyzer
      Result = Data.define(:landing_page, :candidate, :metrics, :reason)

      def initialize(business:, landing_page:, snapshots: nil)
        @business = business
        @landing_page = landing_page
        @snapshots = snapshots
      end

      def call
        validate!
        metrics = analytics
        opportunity = improvement_opportunity(metrics)
        candidate = opportunity ? existing_candidate(opportunity, metrics) || create_candidate!(opportunity, metrics) : nil
        persist_analysis!(metrics, opportunity, candidate)
        Result.new(
          landing_page:,
          candidate:,
          metrics:,
          reason: opportunity ? "候補 ##{candidate.id}" : "比較できる改善余地がまだありません。"
        )
      end

      private

      attr_reader :business, :landing_page, :snapshots

      def validate!
        return if landing_page.business_id == business.id && landing_page.external_landing_page?

        raise ArgumentError, "このBusinessのLPではありません。"
      end

      def analytics
        result = Aicoo::Lovable::LandingPageAnalyticsReader.new(
          business:,
          started_at: 90.days.ago,
          ended_at: Time.current,
          target_paths: [ landing_page.landing_page_url, landing_page.landing_page_ga4_path ],
          snapshots:
        ).call
        {
          "ga4" => result.ga4,
          "gsc" => result.gsc,
          "current_conversion_rate" => current_conversion_rate(result.ga4),
          "business_conversion_rate" => business_conversion_rate,
          "business_gsc_ctr" => business_gsc_ctr,
          "analyzed_at" => Time.current.iso8601
        }
      end

      def improvement_opportunity(metrics)
        cvr_opportunity(metrics) || gsc_opportunity(metrics)
      end

      def cvr_opportunity(metrics)
        current = metrics["current_conversion_rate"]
        benchmark = metrics["business_conversion_rate"]
        sessions = metrics.dig("ga4", "sessions").to_i
        return if current.nil? || benchmark.nil? || sessions.zero? || current >= benchmark

        expected_conversion_gain = ((benchmark - current) * sessions).round(2)
        return unless expected_conversion_gain.positive?

        opportunity(
          type: "cta_improvement",
          target_metric: "conversion_rate",
          current_value: current,
          target_value: benchmark,
          expected_conversion_gain:,
          expected_click_gain: 0,
          current_conversions: metrics.dig("ga4", "conversions").to_i,
          expected_hours: 0.5,
          reason: "CV率#{percentage(current)}がBusiness実績#{percentage(benchmark)}を下回っています。"
        )
      end

      def gsc_opportunity(metrics)
        return unless metrics.dig("gsc", "available") == true

        current = metrics.dig("gsc", "ctr").to_d
        benchmark = metrics["business_gsc_ctr"]
        impressions = metrics.dig("gsc", "impressions").to_i
        conversion_rate = metrics["business_conversion_rate"]
        return if benchmark.nil? || conversion_rate.nil? || impressions.zero? || current >= benchmark

        expected_click_gain = ((benchmark - current) * impressions).round(2)
        expected_conversion_gain = (expected_click_gain * conversion_rate).round(2)
        return unless expected_click_gain.positive?

        opportunity(
          type: "seo_improvement",
          target_metric: "gsc_ctr",
          current_value: current,
          target_value: benchmark,
          expected_conversion_gain:,
          expected_click_gain:,
          current_conversions: metrics.dig("ga4", "conversions").to_i,
          expected_hours: 1.0,
          reason: "GSC CTR #{percentage(current)}がBusiness実績#{percentage(benchmark)}を下回っています。"
        )
      end

      def opportunity(type:, target_metric:, current_value:, target_value:, expected_conversion_gain:, expected_click_gain:, current_conversions:, expected_hours:, reason:)
        value_per_conversion = profit_per_conversion_yen
        success_probability = improvement_success_probability
        raw_profit = (expected_conversion_gain * value_per_conversion).round
        {
          "type" => type,
          "target_metric" => target_metric,
          "current_value" => current_value.to_f,
          "target_value" => target_value.to_f,
          "expected_conversion_gain" => expected_conversion_gain.to_f,
          "expected_click_gain" => expected_click_gain.to_f,
          "expected_cv" => current_conversions + expected_conversion_gain,
          "profit_per_conversion_yen" => value_per_conversion,
          "success_probability" => success_probability,
          "raw_profit_yen" => raw_profit,
          "expected_profit_yen" => (raw_profit * success_probability).round,
          "expected_hours" => expected_hours,
          "expected_hourly_value_yen" => expected_hours.positive? ? (raw_profit * success_probability / expected_hours).round : 0,
          "reason" => reason
        }
      end

      def create_candidate!(opportunity, metrics)
        repository_url = landing_page.landing_page_repository_url
        candidate = business.action_candidates.create!(
          title: "#{landing_page.landing_page_name}の#{improvement_label(opportunity.fetch('type'))}を行う",
          description: "LP単位のGA4/GSC実績から生成。#{opportunity.fetch('reason')}",
          evaluation_reason: opportunity.fetch("reason"),
          action_type: opportunity.fetch("type") == "seo_improvement" ? "seo_improvement" : "ui_improvement",
          status: "proposal",
          generation_source: "lp_learning",
          department: "revenue",
          immediate_value_yen: opportunity.fetch("raw_profit_yen"),
          expected_hours: opportunity.fetch("expected_hours"),
          success_probability: opportunity.fetch("success_probability"),
          confidence_score: confidence_score(metrics),
          data_confidence_score: confidence_score(metrics),
          execution_prompt: execution_prompt(opportunity),
          metadata: candidate_metadata(opportunity, metrics, repository_url)
        )
        candidate
      end

      def candidate_metadata(opportunity, metrics, repository_url)
        {
          "workflow_type" => "external_lp_improvement",
          "execution_mode" => "code_revision",
          "generation_source" => "lp_learning",
          "landing_page_id" => landing_page.id,
          "lp_name" => landing_page.landing_page_name,
          "target_record_id" => landing_page.id,
          "target_url" => landing_page.landing_page_url,
          "target_metric" => opportunity.fetch("target_metric"),
          "change_content" => "LP専用リポジトリで#{improvement_label(opportunity.fetch('type'))}を行う",
          "completion_criteria" => [
            "LP専用リポジトリだけが変更されている",
            "Service本体とRender Serviceは変更されていない",
            "Cloudflare Pages上のLPがPC・スマートフォンで表示できる",
            "GA4 page_pathとGSC URLを維持して再計測できる"
          ],
          "file_changes" => [ "LP repository root" ],
          "before" => "#{opportunity.fetch('target_metric')}=#{opportunity.fetch('current_value')} ",
          "after" => "#{opportunity.fetch('target_metric')}=#{opportunity.fetch('target_value')} を目標",
          "target_repository_name" => repository_name(repository_url),
          "target_repository_type" => "static_site",
          "target_repository_url" => repository_url,
          "target_branch" => landing_page.landing_page_branch,
          "target_deploy_target" => "cloudflare_pages",
          "ga4_page_path" => landing_page.landing_page_ga4_path,
          "gsc_url" => landing_page.metadata.to_h["gsc_url"],
          "lp_expected_value" => opportunity,
          "lp_analytics" => metrics,
          "codex_eligible" => repository_url.present?,
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false,
          "owner_approval_required" => true,
          "service_repository_protected" => true,
          "analysis_fingerprint" => analysis_fingerprint(opportunity, metrics)
        }.compact
      end

      def execution_prompt(opportunity)
        <<~PROMPT
          #{landing_page.landing_page_name} の#{improvement_label(opportunity.fetch('type'))}を行ってください。
          根拠: #{opportunity.fetch('reason')}
          対象: #{landing_page.landing_page_url}
          Repository: #{landing_page.landing_page_repository_url}
          Branch: #{landing_page.landing_page_branch}
          Hosting: Cloudflare Pages

          Service本体、Render、DBは変更せず、LP専用リポジトリだけを変更してください。
        PROMPT
      end

      def existing_candidate(opportunity, metrics)
        fingerprint = analysis_fingerprint(opportunity, metrics)
        business.action_candidates.where(generation_source: "lp_learning").active_for_ranking.find do |candidate|
          candidate.metadata.to_h["analysis_fingerprint"] == fingerprint
        end
      end

      def analysis_fingerprint(opportunity, metrics)
        Digest::SHA256.hexdigest([
          landing_page.id,
          opportunity["type"],
          metrics.dig("ga4", "source_id"),
          metrics.dig("gsc", "source_id"),
          opportunity["current_value"],
          opportunity["target_value"]
        ].join("|"))
      end

      def persist_analysis!(metrics, opportunity, candidate)
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "lp_analytics" => metrics,
          "current_conversion_rate" => metrics["current_conversion_rate"],
          "improvement_target" => opportunity&.dig("type") || landing_page.metadata.to_h["improvement_target"],
          "expected_profit_yen" => candidate&.final_expected_value_yen,
          "expected_cv" => opportunity&.dig("expected_cv"),
          "expected_hourly_value_yen" => candidate&.expected_hourly_value_yen,
          "improvement_candidate_id" => candidate&.id,
          "last_analyzed_at" => Time.current.iso8601,
          "last_candidate_generated_at" => candidate ? Time.current.iso8601 : landing_page.metadata.to_h["last_candidate_generated_at"]
        ).compact)
      end

      def current_conversion_rate(ga4)
        if ga4["available"] == true && ga4["sessions"].to_i.positive?
          return (ga4["conversions"].to_d / ga4["sessions"].to_d).round(6)
        end

        normalize_rate(landing_page.landing_page_conversion_rate)
      end

      def business_conversion_rate
        rows = business.business_metric_dailies.where(recorded_on: 90.days.ago.to_date..Date.current)
        sessions = rows.sum(:sessions)
        return normalize_rate(business.metadata.to_h["conversion_rate"]) if sessions.zero?

        (rows.sum(:conversions).to_d / sessions).round(6)
      end

      def business_gsc_ctr
        rows = business.business_metric_dailies.where(recorded_on: 90.days.ago.to_date..Date.current)
        impressions = rows.sum(:impressions)
        return if impressions.zero?

        (rows.sum(:clicks).to_d / impressions).round(6)
      end

      def profit_per_conversion_yen
        observed = business.revenue_events.revenue.where(occurred_on: 90.days.ago.to_date..Date.current).average(:amount)
        configured = business.metadata.to_h["profit_per_conversion_yen"].presence ||
          business.metadata.to_h["revenue_per_conversion_yen"].presence
        (observed || configured || Aicoo::ArticleOpportunityExpectedProfit::INITIAL_COEFFICIENTS.fetch("profit_per_conversion_yen")).to_d.round
      end

      def improvement_success_probability
        normalize_rate(business.metadata.to_h["lp_improvement_success_probability"]) || 0.5.to_d
      end

      def normalize_rate(value)
        return if value.blank?

        rate = value.to_d
        rate /= 100 if rate > 1
        rate.clamp(0.to_d, 1.to_d)
      end

      def confidence_score(metrics)
        sources = [ metrics.dig("ga4", "available"), metrics.dig("gsc", "available") ].count(true)
        { 0 => 20, 1 => 55, 2 => 80 }.fetch(sources)
      end

      def repository_name(url)
        return if url.blank?

        File.basename(URI.parse(url).path, ".git")
      rescue URI::InvalidURIError
        url.to_s.split("/").last
      end

      def improvement_label(type)
        type == "seo_improvement" ? "SEO改善" : "CTA改善"
      end

      def percentage(value)
        "#{(value.to_d * 100).round(2)}%"
      end
    end
  end
end
