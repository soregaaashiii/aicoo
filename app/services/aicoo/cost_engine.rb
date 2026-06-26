module Aicoo
  class CostEngine
    Estimate = Data.define(
      :source_key,
      :name,
      :enabled,
      :execution_mode,
      :cost_level,
      :estimated_cost_yen,
      :expected_profit_yen,
      :roi,
      :monthly_budget_yen,
      :monthly_spend_yen,
      :monthly_budget_remaining_yen,
      :monthly_run_count,
      :last_run_at,
      :last_error,
      :business_enabled,
      :connection_status,
      :connection_label,
      :connection_status_level,
      :connection_summary,
      :linked,
      :manual,
      :smart,
      :auto,
      :warning
    ) do
      def linked? = linked
      def manual? = manual
      def smart? = smart
      def auto? = auto
    end
    Summary = Data.define(
      :generated_at,
      :profiles,
      :estimates,
      :monthly_api_cost_yen,
      :monthly_budget_yen,
      :roi,
      :auto_count,
      :smart_count,
      :manual_count,
      :warning_count,
      :warnings
    )

    def initialize(business: nil)
      @business = business
    end

    def call
      DataSourceCostProfile.ensure_defaults!
      estimates = DataSourceCostProfile.ordered.map { |profile| estimate(profile.source_key) }
      Summary.new(
        generated_at: Time.current,
        profiles: DataSourceCostProfile.ordered,
        estimates:,
        monthly_api_cost_yen: estimates.sum(&:monthly_spend_yen),
        monthly_budget_yen: estimates.sum(&:monthly_budget_yen),
        roi: ratio(estimates.sum(&:expected_profit_yen), estimates.sum(&:estimated_cost_yen)),
        auto_count: estimates.count(&:auto?),
        smart_count: estimates.count(&:smart?),
        manual_count: estimates.count(&:manual?),
        warning_count: estimates.count { |estimate| estimate.warning.present? },
        warnings: estimates.filter_map(&:warning)
      )
    end

    def estimate(source_key, expected_profit_yen: nil, estimated_cost_yen: nil)
      profile = DataSourceCostProfile.for_source(source_key)
      business_setting = business ? BusinessDataSourceSetting.for_business_and_source(business, source_key) : nil
      business_enabled = business_setting.nil? ? true : business_setting.enabled?
      cost = estimated_cost_yen || profile.average_cost_yen
      expected_profit = expected_profit_yen || profile.average_expected_profit_yen
      Estimate.new(
        source_key:,
        name: profile.name,
        enabled: profile.enabled?,
        execution_mode: profile.execution_mode,
        cost_level: profile.cost_level,
        estimated_cost_yen: cost.to_d,
        expected_profit_yen: expected_profit.to_d,
        roi: ratio(expected_profit, cost),
        monthly_budget_yen: profile.monthly_budget_yen.to_i,
        monthly_spend_yen: profile.monthly_spend_yen.to_i,
        monthly_budget_remaining_yen: profile.monthly_budget_remaining_yen,
        monthly_run_count: profile.monthly_run_count.to_i,
        last_run_at: profile.last_run_at,
        last_error: profile.last_error,
        business_enabled:,
        connection_status: business_setting&.connection_status,
        connection_label: business_setting&.connection_status_label,
        connection_status_level: business_setting&.connection_status_level || "attention",
        connection_summary: business_setting&.connection_summary,
        linked: business_setting&.linked? || false,
        manual: profile.execution_mode == "manual",
        smart: profile.execution_mode == "smart",
        auto: profile.execution_mode == "auto",
        warning: warning_for(profile, business_enabled:, business_setting:)
      )
    end

    def should_smart_run?(source_key, signals: {})
      estimated = estimate(source_key)
      return false unless estimated.enabled && estimated.business_enabled && estimated.smart?
      return false if estimated.monthly_budget_yen.positive? && estimated.monthly_budget_remaining_yen < estimated.estimated_cost_yen

      signals.values.any?(&:present?) && estimated.roi.present? && estimated.roi.to_d >= 1
    end

    private

    attr_reader :business

    def warning_for(profile, business_enabled:, business_setting:)
      return "#{profile.name}は全体設定でOFFです" unless profile.enabled?
      return "#{profile.name}はこのBusinessでOFFです" unless business_enabled
      return "#{profile.name}はBusiness詳細が未紐付けです" if business_setting&.connection_status == "unlinked"
      return "#{profile.name}のBusiness紐付けが要確認です" if business_setting&.connection_status == "needs_attention"
      return "#{profile.name}のBusiness紐付けでエラーがあります" if business_setting&.connection_status == "error"
      return "#{profile.name}の月間予算を超過しています" if profile.monthly_budget_yen.positive? && profile.monthly_budget_remaining_yen.negative?
      return "#{profile.name}でエラーがあります" if profile.last_error.present?
      return "#{profile.name}は高コストです" if profile.cost_level == "high"

      nil
    end

    def ratio(numerator, denominator)
      return nil if denominator.to_d.zero?

      numerator.to_d / denominator.to_d
    end
  end
end
