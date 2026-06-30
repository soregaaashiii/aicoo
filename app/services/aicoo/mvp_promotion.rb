module Aicoo
  class MvpPromotion
    Result = Data.define(:business, :landing_page, :business_service, :action_candidate, :auto_revision_task)

    def initialize(business:, landing_page_id:, operator: "owner")
      @business = business
      @landing_page = business.aicoo_lab_landing_pages.find(landing_page_id)
      @operator = operator
    end

    def call
      summary = summary_for_landing_page
      raise ArgumentError, "LP評価が #{summary.verdict} のためMVP昇格できません。" unless summary.promotable?

      ActiveRecord::Base.transaction do
        business.update!(lifecycle_stage: "mvp")
        business_service = create_business_service!
        action_candidate = create_action_candidate!(summary)
        auto_revision_task = create_auto_revision_task!(action_candidate, summary)
        record_timeline!(summary, business_service, auto_revision_task)

        Result.new(business:, landing_page:, business_service:, action_candidate:, auto_revision_task:)
      end
    end

    private

    attr_reader :business, :landing_page, :operator

    def summary_for_landing_page
      Aicoo::LpEvaluationSummary.for_business(business).find { |row| row.landing_page.id == landing_page.id } ||
        raise(ActiveRecord::RecordNotFound, "LP評価が見つかりません")
    end

    def create_business_service!
      business.business_services.find_or_create_by!(name: "#{business.name} MVP") do |service|
        service.status = "building"
        service.repository = business.codex_repository_name
        service.deploy_target = business.business_execution_profile&.deploy_command.presence || "未設定"
        service.url = nil
        service.domain = landing_page.published_slug
      end
    end

    def create_action_candidate!(summary)
      existing = business.action_candidates.where(
        "metadata ->> 'source' = ? AND metadata ->> 'landing_page_id' = ?",
        "lp_to_mvp_promotion",
        landing_page.id.to_s
      ).first
      return existing if existing

      prompt = Aicoo::MvpDevelopmentPromptBuilder.new(business:, landing_page:, lp_summary: summary).call

      business.action_candidates.create!(
        title: "#{business.name}のMVPを開発する",
        description: "LP検証で#{summary.verdict}判定になったため、最小機能のMVP開発へ進めます。",
        action_type: "build_mvp",
        status: "approved",
        generation_source: "manual",
        department: "new_business",
        success_probability: summary.verdict == "strong" ? 0.7 : 0.55,
        immediate_value_yen: estimated_value_yen(summary),
        expected_hours: 8,
        cost_yen: 0,
        strategic_value_score: summary.verdict == "strong" ? 80 : 65,
        risk_reduction_score: 50,
        confidence_score: summary.verdict == "strong" ? 80 : 65,
        data_confidence_score: summary.pv.positive? ? 70 : 40,
        priority_score: summary.verdict == "strong" ? 90 : 75,
        evaluation_reason: "LP評価 #{summary.verdict}: PV #{summary.pv} / CTA #{summary.cta_clicks} / CV #{summary.cv}",
        execution_prompt: prompt,
        approved_at: Time.current,
        approved_by: operator,
        metadata: {
          "source" => "lp_to_mvp_promotion",
          "landing_page_id" => landing_page.id,
          "lp_verdict" => summary.verdict,
          "lp_pv" => summary.pv,
          "lp_cta_clicks" => summary.cta_clicks,
          "lp_cv" => summary.cv,
          "lp_cvr" => summary.cvr.to_s
        }
      )
    end

    def create_auto_revision_task!(action_candidate, summary)
      existing = business.auto_revision_tasks.where(
        "metadata ->> 'source' = ? AND metadata ->> 'landing_page_id' = ?",
        "lp_to_mvp_promotion",
        landing_page.id.to_s
      ).first
      return existing if existing

      AutoRevisionTask.create!(
        action_candidate:,
        business:,
        title: "#{business.name} MVP開発",
        execution_prompt: action_candidate.execution_prompt,
        priority_score: summary.verdict == "strong" ? 90 : 75,
        generated_by: "lp_to_mvp_promotion",
        risk_level: "medium",
        status: "waiting_approval",
        metadata: {
          "source" => "lp_to_mvp_promotion",
          "landing_page_id" => landing_page.id,
          "action_candidate_id" => action_candidate.id,
          "lp_verdict" => summary.verdict
        }
      )
    end

    def record_timeline!(summary, business_service, auto_revision_task)
      business.business_activity_logs.create!(
        activity_type: "mvp_promoted",
        source_app: "aicoo",
        source_method: "logger",
        resource_type: "Business",
        resource_id: business.id.to_s,
        title: "MVP開発へ昇格",
        occurred_at: Time.current,
        detected_at: Time.current,
        diff_summary: "#{landing_page.public_headline} のLP評価が #{summary.verdict} のためMVPへ昇格しました。",
        idempotency_key: "mvp_promotion:business:#{business.id}:lp:#{landing_page.id}",
        metadata: {
          "operator" => operator,
          "landing_page_id" => landing_page.id,
          "business_service_id" => business_service.id,
          "auto_revision_task_id" => auto_revision_task.id,
          "lp_verdict" => summary.verdict,
          "pv" => summary.pv,
          "cta_clicks" => summary.cta_clicks,
          "cv" => summary.cv
        }
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def estimated_value_yen(summary)
      base = landing_page.assumed_price_yen.to_i
      base = 30_000 if base.zero?
      [ base * [ summary.cv, 1 ].max, 300_000 ].min
    end
  end
end
