module Aicoo
  module LpIntegration
    class BusinessLandingPagePlanner
      Result = Data.define(
        :business,
        :recommendations,
        :total_missing_count,
        :total_expected_profit_yen,
        :generated_at
      )
      BatchResult = Data.define(:business_count, :recommendation_count, :missing_lp_count, :expected_profit_yen)

      CORE_PURPOSES = %w[seo google_ads comparison regional].freeze
      PURPOSE_CAMPAIGN_TYPES = {
        "seo" => "seo",
        "google_ads" => "google_ads",
        "meta_ads" => "meta_ads",
        "comparison" => "comparison",
        "regional" => "seo",
        "sns" => "sns",
        "email" => "email",
        "other" => "other"
      }.freeze
      QUERY_CLUSTER_SIZE = 5
      MAX_SEARCH_LP_COUNT = 20

      def self.refresh_all!(persist: true)
        results = Business.real_businesses.find_each.map { |business| new(business).call(persist:) }
        BatchResult.new(
          business_count: results.size,
          recommendation_count: results.sum { |result| result.recommendations.size },
          missing_lp_count: results.sum(&:total_missing_count),
          expected_profit_yen: results.sum(&:total_expected_profit_yen)
        )
      end

      def initialize(business)
        @business = business
      end

      def call(persist: false)
        recommendations = planning_purposes.filter_map { |purpose| recommendation_for(purpose) }
          .sort_by { |row| -row.fetch("expected_profit_yen") }
        generated_at = Time.current
        result = Result.new(
          business:,
          recommendations:,
          total_missing_count: recommendations.sum { |row| row.fetch("missing_count") },
          total_expected_profit_yen: recommendations.sum { |row| row.fetch("expected_profit_yen") },
          generated_at:
        )
        persist!(result) if persist
        result
      end

      private

      attr_reader :business

      def planning_purposes
        campaign_purposes = campaigns.map { |campaign| planner_purpose(campaign) }
        (CORE_PURPOSES + campaign_purposes).uniq
      end

      def recommendation_for(purpose)
        campaign = campaign_for(purpose)
        pages = landing_pages_for(campaign, purpose)
        desired_count, count_source = desired_count_for(campaign, purpose, pages)
        missing_count = [ desired_count - pages.size, 0 ].max
        return if missing_count.zero?

        expected_profit_per_lp = expected_profit_per_lp_for(pages, campaign)
        expected_cv_per_lp = expected_cv_per_lp_for(pages, campaign, desired_count)
        estimated_hours_per_lp = LandingPageStrategyBuilder::ESTIMATED_WORK_HOURS.fetch(purpose)
        expected_profit_yen = expected_profit_per_lp * missing_count
        estimated_work_hours = estimated_hours_per_lp * missing_count
        {
          "purpose" => purpose,
          "purpose_label" => LandingPageStrategyBuilder::PURPOSES.fetch(purpose),
          "campaign_id" => campaign&.id,
          "campaign_name" => campaign&.name || LandingPageStrategyBuilder::PURPOSES.fetch(purpose),
          "campaign_type" => campaign&.campaign_type || PURPOSE_CAMPAIGN_TYPES.fetch(purpose),
          "existing_count" => pages.size,
          "recommended_count" => desired_count,
          "missing_count" => missing_count,
          "expected_profit_per_lp_yen" => expected_profit_per_lp,
          "expected_profit_yen" => expected_profit_yen,
          "expected_cv_per_lp" => expected_cv_per_lp.to_f.round(2),
          "expected_cv" => (expected_cv_per_lp * missing_count).to_f.round(2),
          "expected_hourly_value_yen" => estimated_work_hours.positive? ? (expected_profit_yen / estimated_work_hours).round : 0,
          "estimated_work_hours" => estimated_work_hours,
          "expected_organic_visits" => expected_traffic(pages, purpose, "gsc", "clicks", missing_count),
          "expected_ad_visits" => expected_ad_visits(pages, purpose, missing_count),
          "count_source" => count_source,
          "expected_value_source" => expected_profit_per_lp.positive? ? "existing_lp_expected_profit" : "insufficient_profit_evidence",
          "reason" => recommendation_reason(purpose, count_source, pages.size, desired_count)
        }
      end

      def desired_count_for(campaign, purpose, pages)
        configured = positive_integer(campaign&.metadata.to_h&.dig("recommended_lp_count")) ||
          positive_integer(campaign&.metadata.to_h&.dig("target_lp_count"))
        return [ configured, "campaign_setting" ] if configured

        expected_cv = median(pages.filter_map { |page| positive_decimal(page.metadata.to_h["expected_cv"]) })
        if campaign&.target_conversions.to_d.positive? && expected_cv&.positive?
          target_count = (campaign.target_conversions.to_d / expected_cv).ceil
          return [ [ target_count, pages.size ].max, "campaign_conversion_target" ]
        end

        if purpose == "seo" && search_query_count.positive?
          target_count = [ (search_query_count.to_d / QUERY_CLUSTER_SIZE).ceil, MAX_SEARCH_LP_COUNT ].min
          return [ [ target_count, pages.size, 1 ].max, "stored_search_demand" ]
        end

        [ [ pages.size, 1 ].max, campaign ? "active_campaign_baseline" : "business_portfolio_baseline" ]
      end

      def expected_profit_per_lp_for(pages, campaign)
        values = pages.filter_map { |page| positive_integer(page.metadata.to_h["expected_profit_yen"]) }
        if values.empty?
          candidates = business.action_candidates.active_for_ranking.where(action_type: %w[build_lp lp_experiment ui_improvement])
          candidates = candidates.select { |candidate| candidate.metadata.to_h["campaign_id"].to_i == campaign.id } if campaign
          values = candidates.filter_map { |candidate| positive_integer(candidate.final_expected_value_yen) }
        end
        (median(values) || 0).to_i
      end

      def expected_cv_per_lp_for(pages, campaign, desired_count)
        values = pages.filter_map { |page| positive_decimal(page.metadata.to_h["expected_cv"]) }
        return median(values) if values.any?
        return campaign.target_conversions.to_d / desired_count if campaign&.target_conversions.to_d.positive? && desired_count.positive?

        0.to_d
      end

      def expected_traffic(pages, purpose, source, metric, missing_count)
        return 0 unless purpose.in?(%w[seo comparison regional])

        values = pages.filter_map do |page|
          value = page.metadata.to_h.dig("lp_analytics", source, metric)
          positive_integer(value)
        end
        ((median(values) || 0) * missing_count).to_i
      end

      def expected_ad_visits(pages, purpose, missing_count)
        return 0 unless purpose.in?(%w[google_ads meta_ads sns email])

        values = pages.filter_map do |page|
          positive_integer(page.metadata.to_h.dig("lp_analytics", "ga4", "pageviews"))
        end
        ((median(values) || 0) * missing_count).to_i
      end

      def recommendation_reason(purpose, source, existing_count, desired_count)
        "#{LandingPageStrategyBuilder::PURPOSES.fetch(purpose)}は#{source_label(source)}から#{desired_count}件が必要と判定し、現在#{existing_count}件です。"
      end

      def source_label(source)
        {
          "campaign_setting" => "Campaign設定",
          "campaign_conversion_target" => "目標CVと既存LP実績",
          "stored_search_demand" => "保存済み検索需要",
          "active_campaign_baseline" => "運用中Campaign",
          "business_portfolio_baseline" => "Businessの基本集客構成"
        }.fetch(source)
      end

      def campaign_for(purpose)
        return campaigns.find { |campaign| campaign.metadata.to_h["planner_purpose"] == "regional" || campaign.name.include?("地域") } if purpose == "regional"

        campaigns.find { |campaign| campaign.campaign_type == PURPOSE_CAMPAIGN_TYPES.fetch(purpose) }
      end

      def landing_pages_for(campaign, purpose)
        return [] unless campaign

        pages = campaign.landing_pages.active.to_a
        if purpose == "regional"
          pages.select { |page| page.metadata.to_h["creation_purpose"] == "regional" }
        elsif purpose == "seo"
          pages.reject { |page| page.metadata.to_h["creation_purpose"] == "regional" }
        else
          pages
        end
      end

      def campaigns
        @campaigns ||= business.business_campaigns.active.includes(:landing_pages).to_a
      end

      def search_query_count
        @search_query_count ||= business.business_serp_keywords.where.not(status: %w[rejected archived]).count
      end

      def planner_purpose(campaign)
        return "regional" if campaign.metadata.to_h["planner_purpose"] == "regional" || campaign.name.include?("地域")

        campaign.campaign_type.presence_in(LandingPageStrategyBuilder::PURPOSES.keys) || "other"
      end

      def persist!(result)
        business.update!(metadata: business.metadata.to_h.merge(
          "lp_improvement_planner" => {
            "generated_at" => result.generated_at.iso8601,
            "recommendations" => result.recommendations,
            "total_missing_count" => result.total_missing_count,
            "total_expected_profit_yen" => result.total_expected_profit_yen,
            "ranking_metric" => "expected_profit_yen"
          }
        ))
      end

      def median(values)
        sorted = values.compact.sort
        return if sorted.empty?

        middle = sorted.length / 2
        sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.to_d
      end

      def positive_integer(value)
        number = value.to_i
        number if number.positive?
      end

      def positive_decimal(value)
        number = value.to_d
        number if number.positive?
      end
    end
  end
end
