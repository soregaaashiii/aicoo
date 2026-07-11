module Aicoo
  class TodayActionEligibilityRepair
    Result = Data.define(
      :checked,
      :external_url_excluded,
      :invalid_path_excluded,
      :unrealistic_profit_excluded,
      :duplicate_grouped,
      :exploring_not_actionable,
      :eligible,
      :failed,
      :applied
    )

    def self.call(apply: false)
      new(apply:).call
    end

    def initialize(apply: false)
      @apply = apply
      @board = TodayActionBoard.new(mode: "revenue")
      @counts = Hash.new(0)
    end

    def call
      repair_action_candidates
      inspect_new_businesses

      Result.new(
        checked: counts[:checked],
        external_url_excluded: counts[:external_url_excluded],
        invalid_path_excluded: counts[:invalid_path_excluded],
        unrealistic_profit_excluded: counts[:unrealistic_profit_excluded],
        duplicate_grouped: counts[:duplicate_grouped],
        exploring_not_actionable: counts[:exploring_not_actionable],
        eligible: counts[:eligible],
        failed: counts[:failed],
        applied: apply
      )
    end

    private

    attr_reader :apply, :board, :counts

    def repair_action_candidates
      ActionCandidate.active_for_ranking.includes(:business, :auto_revision_tasks).find_each do |candidate|
        counts[:checked] += 1
        reason = exclusion_reason_for(candidate)
        if reason.present?
          increment_reason(reason)
          write_exclusion(candidate, reason) if apply
        else
          counts[:eligible] += 1
        end
      rescue StandardError => error
        counts[:failed] += 1
        Rails.logger.warn({ event: "today_action_eligibility_repair_failed", action_candidate_id: candidate&.id, error: error.message }.to_json)
      end
    end

    def inspect_new_businesses
      businesses = Business.real_businesses
        .where(status: %w[discovered draft exploring])
        .where(resource_status: %w[active watch])
        .where("created_by_aicoo = ? OR business_type = ?", true, "exploration")
        .to_a

      grouped = businesses.group_by { |business| board.send(:new_business_group_key, business) }
      counts[:duplicate_grouped] = grouped.values.sum { |group| [ group.size - 1, 0 ].max }
      counts[:exploring_not_actionable] = businesses.count { |business| !board.send(:new_business_today_actionable?, business) }
    end

    def exclusion_reason_for(candidate)
      execution_mode = ActionCandidateEvidencePresenter.new(candidate).execution_mode.to_s
      approval_task = board.send(:approval_required_task, candidate)
      base_reason = board.send(:today_exclusion_reason, candidate, execution_mode, approval_task)
      return base_reason if base_reason.present?

      return "missing_concrete_task" if board.send(:concrete_task_for, candidate, ActionCandidateEvidencePresenter.new(candidate), ActionCandidateEvidencePresenter.new(candidate).action_plan).blank?
      return "missing_target" if board.send(:target_for, ActionCandidateEvidencePresenter.new(candidate), ActionCandidateEvidencePresenter.new(candidate).action_plan).blank?
      return "missing_owner_next_step" if board.send(:owner_next_step_for, ActionCandidateEvidencePresenter.new(candidate), ActionCandidateEvidencePresenter.new(candidate).action_plan, approval_task).blank?

      nil
    end

    def increment_reason(reason)
      case reason
      when "external_target_url"
        counts[:external_url_excluded] += 1
      when "invalid_target_path", "missing_slug", "target_page_not_found", "target_type_mismatch"
        counts[:invalid_path_excluded] += 1
      when "unrealistic_expected_profit"
        counts[:unrealistic_profit_excluded] += 1
      end
    end

    def write_exclusion(candidate, reason)
      metadata = candidate.metadata.to_h
      candidate.update_columns(
        metadata: metadata.merge(
          "today_exclusion_reason" => reason,
          "today_excluded_at" => Time.current.iso8601,
          "today_exclusion_checked_at" => Time.current.iso8601,
          "today_mode" => "revenue",
          "detected_target_url" => board.send(:detected_target_url_for, candidate)
        ),
        updated_at: Time.current
      )
    end
  end
end
