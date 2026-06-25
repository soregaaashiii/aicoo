module Aicoo
  class OwnerExecutionQueueBuilder
    Result = Data.define(:created, :skipped, :high_risk)

    def initialize(due_on: Date.current, generated_from: "manual", setting: AicooSetting.current)
      @due_on = due_on.to_date
      @generated_from = generated_from
      @setting = setting
    end

    def call
      created = []
      skipped = []
      high_risk = []

      candidates.each do |attributes|
        risk_level = attributes.fetch(:risk_level)
        unless setting.owner_queue_allows_risk?(risk_level)
          high_risk << attributes if risk_level == "high"
          skipped << attributes
          next
        end
        break if created.size >= setting.daily_owner_queue_limit.to_i

        item = create_item(attributes)
        item ? created << item : skipped << attributes
      end

      Result.new(created:, skipped:, high_risk:)
    end

    private

    attr_reader :due_on, :generated_from, :setting

    def candidates
      (
        result_registration_candidates +
        calibration_candidates +
        codex_prompt_draft_needed_candidates +
        action_candidate_candidates +
        codex_prompt_draft_candidates +
        opportunity_candidates
      ).sort_by do |attributes|
        [
          -attributes.fetch(:priority_score).to_d,
          -attributes.fetch(:expected_value_yen).to_i,
          attributes.fetch(:title)
        ]
      end
    end

    def create_item(attributes)
      return if OwnerExecutionQueueItem.exists?(item_type: attributes.fetch(:item_type), item_id: attributes.fetch(:item_id), due_on:)

      OwnerExecutionQueueItem.create!(attributes.merge(generated_from:, due_on:))
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def result_registration_candidates
      ActionExecution.includes(action_candidate: :business).completed_without_result.map do |execution|
        candidate = execution.action_candidate
        build_attributes(
          item_type: "result_registration",
          item_id: execution.id,
          business: candidate.business,
          title: "#{candidate.title} の結果登録",
          expected_value_yen: candidate.final_expected_value_yen || candidate.immediate_value_yen,
          risk_level: "low",
          reason: "完了済みExecutionのActionResultが未登録です。",
          base_score: 90_000,
          metadata: { "action_candidate_id" => candidate.id }
        )
      end
    end

    def calibration_candidates
      ActionPredictionCalibration.where(approval_status: "pending").map do |calibration|
        risk_level = calibration.warning_level == "danger" ? "high" : "medium"
        build_attributes(
          item_type: "calibration",
          item_id: calibration.id,
          business: nil,
          title: "#{calibration.action_type} の評価式補正を確認",
          expected_value_yen: 0,
          risk_level:,
          reason: calibration.warning_reason.presence || "評価式補正が承認待ちです。",
          base_score: risk_level == "high" ? 85_000 : 60_000,
          metadata: { "action_type" => calibration.action_type, "warning_level" => calibration.warning_level }
        )
      end
    end

    def action_candidate_candidates
      ActionCandidate.includes(:business, :codex_prompt_drafts).where(status: "approved").select { |candidate| candidate.codex_prompt_drafts.any? }.map do |candidate|
        build_attributes(
          item_type: "action_candidate",
          item_id: candidate.id,
          business: candidate.business,
          title: "#{candidate.title} を実行準備",
          expected_value_yen: candidate.final_expected_value_yen || candidate.immediate_value_yen,
          risk_level: AutoRevisionTask.risk_level_for(candidate),
          reason: "承認済みActionCandidateです。実行またはCodex Prompt化を判断してください。",
          base_score: 70_000 + candidate.final_score.to_d,
          metadata: { "action_type" => candidate.action_type, "status" => candidate.status }
        )
      end
    end

    def codex_prompt_draft_needed_candidates
      ActionCandidate.includes(:business, :codex_prompt_drafts).where(status: "approved").select { |candidate| candidate.codex_prompt_drafts.empty? }.map do |candidate|
        build_attributes(
          item_type: "action_candidate",
          item_id: candidate.id,
          business: candidate.business,
          title: "#{candidate.title} のCodex Promptを生成",
          expected_value_yen: candidate.final_expected_value_yen || candidate.immediate_value_yen,
          risk_level: AutoRevisionTask.risk_level_for(candidate),
          reason: "CodexPromptDraftが未生成です。",
          base_score: 65_000 + candidate.final_score.to_d,
          metadata: { "queue_purpose" => "codex_prompt_draft_needed" }
        )
      end
    end

    def codex_prompt_draft_candidates
      CodexPromptDraft.includes(:business).where(status: %w[draft approved]).map do |draft|
        build_attributes(
          item_type: "codex_prompt_draft",
          item_id: draft.id,
          business: draft.business,
          title: "#{draft.title} を確認",
          expected_value_yen: draft.metadata.to_h["expected_value_yen"].to_i,
          risk_level: draft.risk_level,
          reason: "CodexPromptDraftが#{draft.status}です。コピーまたは承認を判断してください。",
          base_score: draft.status == "approved" ? 55_000 : 45_000,
          metadata: { "status" => draft.status, "project_key" => draft.project_key }
        )
      end
    end

    def opportunity_candidates
      OpportunityDiscoveryItem.where(status: "pending").map do |opportunity|
        confidence_bonus = opportunity.confidence.to_d * 120
        value_bonus = opportunity.expected_value_yen.to_i / 10
        build_attributes(
          item_type: "opportunity",
          item_id: opportunity.id,
          business: opportunity.business,
          title: opportunity.title,
          expected_value_yen: opportunity.expected_value_yen,
          risk_level: opportunity.confidence.to_i >= 80 ? "low" : "medium",
          reason: "pending Opportunityです。承認またはActionCandidate化を判断してください。",
          base_score: 40_000 + confidence_bonus + value_bonus,
          metadata: { "confidence" => opportunity.confidence&.to_s, "source_type" => opportunity.source_type }
        )
      end
    end

    def build_attributes(item_type:, item_id:, business:, title:, expected_value_yen:, risk_level:, reason:, base_score:, metadata:)
      {
        item_type:,
        item_id:,
        business:,
        title:,
        expected_value_yen: expected_value_yen.to_i,
        risk_level:,
        reason:,
        priority_score: base_score.to_d,
        status: "pending",
        metadata:
      }
    end
  end
end
