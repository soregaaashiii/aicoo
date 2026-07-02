module Aicoo
  module Serp
    class ScanPlan
      DEFAULT_LIMIT = 10
      DEFAULT_UNIT_RESULT_COST_YEN = 0.33.to_d
      METADATA_LIMIT_KEY = "serp_scan_limit"
      METADATA_UNIT_COST_KEY = "unit_result_cost_yen"

      Result = Data.define(
        :provider,
        :limit,
        :target_business_count,
        :candidate_keyword_count,
        :estimated_api_calls,
        :estimated_cost_yen,
        :monthly_budget_yen,
        :current_month_spend_yen,
        :projected_month_spend_yen,
        :budget_exceeded,
        :limit_warning_level,
        :limit_warning_message
      )

      def self.configured_limit(profile = DataSourceCostProfile.for_source("serp"))
        profile.metadata.to_h.fetch(METADATA_LIMIT_KEY, DEFAULT_LIMIT).to_i.clamp(1, 500)
      end

      def self.save_limit!(limit)
        profile = DataSourceCostProfile.for_source("serp")
        value = limit.to_i
        value = DEFAULT_LIMIT unless value.positive?
        profile.update!(metadata: profile.metadata.to_h.merge(METADATA_LIMIT_KEY => value))
        value
      end

      def initialize(profile: DataSourceCostProfile.for_source("serp"), provider: nil, target_businesses: nil)
        @profile = profile
        @provider = (provider.presence || ENV["AICOO_SERP_PROVIDER"].presence || "serper").to_s
        @target_businesses = target_businesses
      end

      def call(limit: nil)
        resolved_limit = (limit.presence || self.class.configured_limit(profile)).to_i
        query_count = target_businesses.sum { |business| queries_for(business).size }
        estimated_api_calls = query_count * resolved_limit
        estimated_cost = (estimated_api_calls * unit_result_cost_yen).round
        projected_spend = profile.monthly_spend_yen.to_i + estimated_cost

        Result.new(
          provider:,
          limit: resolved_limit,
          target_business_count: target_businesses.size,
          candidate_keyword_count: query_count,
          estimated_api_calls:,
          estimated_cost_yen: estimated_cost,
          monthly_budget_yen: profile.monthly_budget_yen.to_i,
          current_month_spend_yen: profile.monthly_spend_yen.to_i,
          projected_month_spend_yen: projected_spend,
          budget_exceeded: profile.monthly_budget_yen.to_i.positive? && projected_spend > profile.monthly_budget_yen.to_i,
          limit_warning_level: limit_warning(resolved_limit).fetch(:level),
          limit_warning_message: limit_warning(resolved_limit).fetch(:message)
        )
      end

      private

      attr_reader :profile, :provider

      def target_businesses
        @target_businesses ||= Business.real_businesses
                                      .where(status: "launched", serp_enabled: true)
                                      .includes(:business_data_source_settings, :business_serp_keywords, :serp_queries)
                                      .order(:name)
                                      .to_a
      end

      def unit_result_cost_yen
        profile.metadata.to_h.fetch(METADATA_UNIT_COST_KEY, DEFAULT_UNIT_RESULT_COST_YEN).to_d
      end

      def queries_for(business)
        Aicoo::Serp::ScanRunner.queries_for_business(business)
      end

      def limit_warning(limit)
        case limit.to_i
        when 1..20
          { level: "safe", message: "推奨範囲です" }
        when 21..50
          { level: "notice", message: "API消費が増えます" }
        when 51..100
          { level: "warning", message: "高コストです" }
        else
          { level: "danger", message: "本当に実行しますか？" }
        end
      end
    end
  end
end
