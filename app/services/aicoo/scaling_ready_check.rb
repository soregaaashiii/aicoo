module Aicoo
  class ScalingReadyCheck
    Check = Data.define(:key, :label, :passed, :message)
    Result = Data.define(:checks) do
      def ready?
        checks.all?(&:passed)
      end

      def warnings
        checks.reject(&:passed)
      end
    end

    def initialize(business, scaling_summary = nil)
      @business = business
      @scaling_summary = scaling_summary || Aicoo::ScalingEvaluationSummary.for_business(business)
    end

    def call
      Result.new(checks: [
        production_stage_check,
        revenue_or_paid_user_check,
        cvr_check,
        retention_check,
        channel_check,
        cac_check,
        ltv_check,
        improvement_candidate_check
      ])
    end

    private

    attr_reader :business, :scaling_summary

    def production_stage_check
      passed = business.lifecycle_stage == "production"
      Check.new(:production_stage, "production状態である", passed, passed ? "production運用中です。" : "Scaling前にproductionへ昇格してください。")
    end

    def revenue_or_paid_user_check
      passed = scaling_summary.monthly_revenue_yen.positive? || scaling_summary.paid_users.positive?
      Check.new(:revenue_or_paid_user, "売上または有料ユーザーがある", passed, passed ? "売上または有料ユーザーがあります。" : "売上/有料ユーザーがまだありません。")
    end

    def cvr_check
      passed = business.business_metric_dailies.where(recorded_on: 30.days.ago.to_date..Date.current).sum(:sessions).positive?
      Check.new(:cvr, "CVRが取得できている", passed, passed ? "CVR算出に必要なsessionsがあります。" : "CVR算出用のsessions/conversionsが不足しています。")
    end

    def retention_check
      passed = scaling_summary.retention_rate.positive?
      Check.new(:retention, "継続率または利用継続データがある", passed, passed ? "継続率を算出できます。" : "継続率または利用継続データがありません。")
    end

    def channel_check
      passed = business.business_services.any? { |service| service.metadata.to_h["primary_channel"].present? } ||
               business.serp_analyses.exists? ||
               business.business_metric_dailies.where(recorded_on: 30.days.ago.to_date..Date.current).sum(:impressions).positive?
      Check.new(:channel, "主要獲得チャネルが分かる", passed, passed ? "主要チャネルの手がかりがあります。" : "主要獲得チャネルを記録してください。")
    end

    def cac_check
      passed = scaling_summary.cac_hypothesis_yen.positive?
      Check.new(:cac, "CAC仮説がある", passed, passed ? "CAC仮説があります。" : "CAC仮説を設定してください。")
    end

    def ltv_check
      passed = scaling_summary.ltv_hypothesis_yen.positive?
      Check.new(:ltv, "LTV仮説がある", passed, passed ? "LTV仮説があります。" : "LTV仮説を設定してください。")
    end

    def improvement_candidate_check
      passed = business.action_candidates.active_for_ranking.exists? || scaling_summary.improvement_room.any?
      Check.new(:improvement_candidate, "改善候補がある", passed, passed ? "改善候補または改善余地があります。" : "改善候補を作成してください。")
    end
  end
end
