module Aicoo
  class ProductionPromotion
    Result = Data.define(:business, :business_service, :action_candidate, :auto_revision_task)

    def initialize(business:, business_service_id:, operator: "owner")
      @business = business
      @business_service = business.business_services.find(business_service_id)
      @operator = operator
    end

    def call
      summary = summary_for_service
      raise ArgumentError, "MVP評価が #{summary.verdict} のため本番昇格できません。" unless summary.promotable?

      ActiveRecord::Base.transaction do
        business.update!(lifecycle_stage: "production", status: "launched", launched: true)
        business_service.update!(status: "production")
        action_candidate = create_action_candidate!(summary)
        auto_revision_task = create_auto_revision_task!(action_candidate, summary)
        record_timeline!(summary, auto_revision_task)

        Result.new(business:, business_service:, action_candidate:, auto_revision_task:)
      end
    end

    private

    attr_reader :business, :business_service, :operator

    def summary_for_service
      Aicoo::MvpEvaluationSummary.for_business(business).find { |row| row.business_service.id == business_service.id } ||
        raise(ActiveRecord::RecordNotFound, "MVP評価が見つかりません")
    end

    def create_action_candidate!(summary)
      existing = business.action_candidates.where(
        "metadata ->> 'source' = ? AND metadata ->> 'business_service_id' = ?",
        "mvp_to_production_promotion",
        business_service.id.to_s
      ).first
      return existing if existing

      prompt = Aicoo::ProductionDevelopmentPromptBuilder.new(business:, business_service:, mvp_summary: summary).call

      business.action_candidates.create!(
        title: "#{business.name}を本番運用へ整える",
        description: "MVP評価で#{summary.verdict}判定になったため、production運用に必要な課金・権限・監視を整えます。",
        action_type: "feature_development",
        status: "approved",
        generation_source: "manual",
        department: "new_business",
        success_probability: summary.verdict == "strong" ? 0.75 : 0.6,
        immediate_value_yen: estimated_value_yen(summary),
        expected_hours: 12,
        cost_yen: 0,
        strategic_value_score: summary.verdict == "strong" ? 85 : 70,
        risk_reduction_score: 65,
        confidence_score: summary.verdict == "strong" ? 85 : 70,
        data_confidence_score: summary.registrations.positive? ? 75 : 45,
        priority_score: summary.verdict == "strong" ? 92 : 78,
        evaluation_reason: "MVP評価 #{summary.verdict}: 登録 #{summary.registrations} / 有料 #{summary.paid_users} / 売上 ¥#{summary.revenue_yen}",
        execution_prompt: prompt,
        approved_at: Time.current,
        approved_by: operator,
        metadata: {
          "source" => "mvp_to_production_promotion",
          "business_service_id" => business_service.id,
          "mvp_verdict" => summary.verdict,
          "registrations" => summary.registrations,
          "active_users" => summary.active_users,
          "paid_users" => summary.paid_users,
          "revenue_yen" => summary.revenue_yen
        }
      )
    end

    def create_auto_revision_task!(action_candidate, summary)
      existing = business.auto_revision_tasks.where(
        "metadata ->> 'source' = ? AND metadata ->> 'business_service_id' = ?",
        "mvp_to_production_promotion",
        business_service.id.to_s
      ).first
      return existing if existing

      AutoRevisionTask.create!(
        action_candidate:,
        business:,
        title: "#{business.name} 本番運用準備",
        execution_prompt: action_candidate.execution_prompt,
        priority_score: summary.verdict == "strong" ? 92 : 78,
        generated_by: "mvp_to_production_promotion",
        risk_level: "medium",
        status: "waiting_approval",
        metadata: {
          "source" => "mvp_to_production_promotion",
          "business_service_id" => business_service.id,
          "action_candidate_id" => action_candidate.id,
          "mvp_verdict" => summary.verdict
        }
      )
    end

    def record_timeline!(summary, auto_revision_task)
      BusinessActivityLog.record!(
        business:,
        attributes: {
          activity_type: "production_promoted",
          source_app: "aicoo",
          source_method: "logger",
          resource_type: "BusinessService",
          resource_id: business_service.id.to_s,
          title: "本番運用へ昇格",
          occurred_at: Time.current,
          detected_at: Time.current,
          diff_summary: "#{business_service.name} のMVP評価が #{summary.verdict} のためproductionへ昇格しました。",
          idempotency_key: "production_promotion:business:#{business.id}:service:#{business_service.id}",
          metadata: {
            "operator" => operator,
            "business_service_id" => business_service.id,
            "auto_revision_task_id" => auto_revision_task.id,
            "mvp_verdict" => summary.verdict,
            "registrations" => summary.registrations,
            "active_users" => summary.active_users,
            "paid_users" => summary.paid_users,
            "revenue_yen" => summary.revenue_yen
          }
        }
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def estimated_value_yen(summary)
      return summary.revenue_yen * 3 if summary.revenue_yen.positive?

      [ summary.paid_users * 20_000, summary.registrations * 5_000, 50_000 ].max
    end
  end
end
