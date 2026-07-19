module Aicoo
  class ScalingPromotion
    Result = Data.define(:business, :action_candidate, :auto_revision_task)

    def initialize(business:, operator: "owner")
      @business = business
      @operator = operator
    end

    def call
      summary = Aicoo::ScalingEvaluationSummary.for_business(business)
      raise ArgumentError, "Scaling評価が #{summary.verdict} のため昇格できません。" unless summary.promotable?

      ActiveRecord::Base.transaction do
        business.update!(lifecycle_stage: "scaling")
        action_candidate = create_action_candidate!(summary)
        auto_revision_task = create_auto_revision_task!(action_candidate, summary)
        record_timeline!(summary, auto_revision_task)

        Result.new(business:, action_candidate:, auto_revision_task:)
      end
    end

    private

    attr_reader :business, :operator

    def create_action_candidate!(summary)
      existing = business.action_candidates.where("metadata ->> 'source' = ?", "production_to_scaling_promotion").first
      return existing if existing

      plan = Aicoo::ScalingPlanBuilder.new(business:, scaling_summary: summary).call

      business.action_candidates.create!(
        title: "#{business.name}のScaling計画を実行する",
        description: "production評価で#{summary.verdict}判定になったため、投資上限を守ってScaling施策へ進めます。",
        action_type: "sales",
        status: "approved",
        generation_source: "manual",
        department: "revenue",
        success_probability: summary.verdict == "strong" ? 0.75 : 0.6,
        immediate_value_yen: estimated_value_yen(summary),
        expected_hours: 6,
        cost_yen: budget_limit_yen(summary),
        strategic_value_score: summary.verdict == "strong" ? 90 : 75,
        risk_reduction_score: 55,
        confidence_score: summary.verdict == "strong" ? 85 : 70,
        data_confidence_score: 75,
        priority_score: summary.verdict == "strong" ? 95 : 82,
        evaluation_reason: "Scaling評価 #{summary.verdict}: 月間売上 ¥#{summary.monthly_revenue_yen} / 有料 #{summary.paid_users} / 粗利 ¥#{summary.gross_profit_yen}",
        execution_prompt: plan,
        approved_at: Time.current,
        approved_by: operator,
        metadata: {
          "source" => "production_to_scaling_promotion",
          "scaling_verdict" => summary.verdict,
          "monthly_revenue_yen" => summary.monthly_revenue_yen,
          "paid_users" => summary.paid_users,
          "retention_rate" => summary.retention_rate.to_s,
          "cvr" => summary.cvr.to_s,
          "recommended_investment" => summary.recommended_investment
        }
      )
    end

    def create_auto_revision_task!(action_candidate, summary)
      existing = business.auto_revision_tasks.where("metadata ->> 'source' = ?", "production_to_scaling_promotion").first
      return existing if existing

      AutoRevisionTask.create!(
        action_candidate:,
        business:,
        title: "#{business.name} Scaling計画",
        execution_prompt: action_candidate.execution_prompt,
        priority_score: summary.verdict == "strong" ? 95 : 82,
        generated_by: "production_to_scaling_promotion",
        risk_level: "medium",
        status: "waiting_approval",
        metadata: {
          "source" => "production_to_scaling_promotion",
          "action_candidate_id" => action_candidate.id,
          "scaling_verdict" => summary.verdict,
          "recommended_investment" => summary.recommended_investment
        }
      )
    end

    def record_timeline!(summary, auto_revision_task)
      BusinessActivityLog.record!(
        business:,
        attributes: {
          activity_type: "scaling_promoted",
          source_app: "aicoo",
          source_method: "logger",
          resource_type: "Business",
          resource_id: business.id.to_s,
          title: "Scalingへ昇格",
          occurred_at: Time.current,
          detected_at: Time.current,
          diff_summary: "production評価が #{summary.verdict} のためScalingへ昇格しました。",
          idempotency_key: "scaling_promotion:business:#{business.id}",
          metadata: {
            "operator" => operator,
            "auto_revision_task_id" => auto_revision_task.id,
            "scaling_verdict" => summary.verdict,
            "monthly_revenue_yen" => summary.monthly_revenue_yen,
            "paid_users" => summary.paid_users,
            "recommended_investment" => summary.recommended_investment
          }
        }
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def estimated_value_yen(summary)
      [ summary.gross_profit_yen * 2, summary.monthly_revenue_yen, 50_000 ].max
    end

    def budget_limit_yen(summary)
      [ summary.gross_profit_yen * 0.3, 10_000 ].max.round
    end
  end
end
