module Aicoo
  class TodayLearningReflectionDiagnostic
    ModeResult = Data.define(
      :mode,
      :today_eligible,
      :today_exclusion_reason,
      :duplicate_suppressed,
      :already_executed,
      :approval_required,
      :included_in_candidate_items,
      :included_in_action_candidate_items,
      :included_in_ranking_input,
      :included_after_ranking,
      :included_in_today_board,
      :display_position,
      :final_result
    )
    Result = Data.define(
      :candidate_id,
      :business_id,
      :candidate_exists,
      :status,
      :execution_mode,
      :generation_source,
      :action_type,
      :total_expected_value_yen,
      :learning_applied,
      :expected_value_updated,
      :today_eligible,
      :today_exclusion_reason,
      :duplicate_suppressed,
      :already_executed,
      :approval_required,
      :included_in_candidate_items,
      :included_in_action_candidate_items,
      :included_in_ranking_input,
      :included_after_ranking,
      :included_in_today_board,
      :display_position,
      :final_result,
      :modes
    )

    def initialize(candidate_id:)
      @candidate_id = candidate_id.to_i
    end

    def call
      candidate = ActionCandidate.includes(:business, :action_result, :action_execution, :auto_revision_tasks).find_by(id: candidate_id)
      return missing_result unless candidate

      modes = TodayActionBoard::MODES.map { |mode| diagnose_mode(candidate, mode) }
      exclusion_reasons = modes.filter_map(&:today_exclusion_reason).uniq
      display_position = modes.filter_map(&:display_position).min

      Result.new(
        candidate_id: candidate.id,
        business_id: candidate.business_id,
        candidate_exists: true,
        status: candidate.status,
        execution_mode: execution_mode_for(candidate),
        generation_source: candidate.generation_source,
        action_type: candidate.action_type,
        total_expected_value_yen: total_expected_value_yen(candidate),
        learning_applied: learning_applied?(candidate),
        expected_value_updated: expected_value_updated?(candidate),
        today_eligible: modes.any?(&:today_eligible),
        today_exclusion_reason: exclusion_reasons.join(",").presence,
        duplicate_suppressed: modes.any?(&:duplicate_suppressed),
        already_executed: candidate.executed?,
        approval_required: modes.any?(&:approval_required),
        included_in_candidate_items: modes.any?(&:included_in_candidate_items),
        included_in_action_candidate_items: modes.any?(&:included_in_action_candidate_items),
        included_in_ranking_input: modes.any?(&:included_in_ranking_input),
        included_after_ranking: modes.any?(&:included_after_ranking),
        included_in_today_board: modes.any?(&:included_in_today_board),
        display_position:,
        final_result: modes.any?(&:included_in_today_board) ? "included_in_today_board" : "excluded:#{exclusion_reasons.join(',').presence || 'unknown'}",
        modes:
      )
    end

    private

    attr_reader :candidate_id

    def diagnose_mode(candidate, mode)
      per_page = [ ActionCandidate.count + 250, 1_000 ].max
      board = TodayActionBoard.new(mode:, per_page:)
      candidate_items = board.send(:candidate_items)
      ranking_input = board.send(:select_today_items, candidate_items)
      board_result = ActionExpectedValueRanking.new(items: ranking_input, mode:, per_page:).call

      candidate_item = find_candidate_item(candidate_items, candidate)
      ranking_input_item = find_candidate_item(ranking_input, candidate)
      ranked_item = find_candidate_item(board_result.items, candidate)
      approval_required = board.send(:approval_required_task, candidate).present?
      duplicate_suppressed = (candidate_item.present? && ranking_input_item.blank?) ||
        candidate.metadata.to_h["today_exclusion_reason"].to_s.start_with?("duplicate_suppressed")
      exclusion_reason = exclusion_reason_for(
        candidate,
        board:,
        candidate_item:,
        ranking_input_item:,
        ranked_item:,
        approval_required:,
        duplicate_suppressed:
      )

      ModeResult.new(
        mode:,
        today_eligible: ranked_item.present?,
        today_exclusion_reason: exclusion_reason,
        duplicate_suppressed:,
        already_executed: candidate.executed?,
        approval_required:,
        included_in_candidate_items: candidate_item.present?,
        included_in_action_candidate_items: candidate_item.present?,
        included_in_ranking_input: ranking_input_item.present?,
        included_after_ranking: ranked_item.present?,
        included_in_today_board: ranked_item.present?,
        display_position: ranked_item&.rank,
        final_result: ranked_item.present? ? "included" : "excluded:#{exclusion_reason || 'unknown'}"
      )
    end

    def exclusion_reason_for(candidate, board:, candidate_item:, ranking_input_item:, ranked_item:, approval_required:, duplicate_suppressed:)
      return nil if ranked_item
      return "already_executed" if candidate.executed?

      presenter = ActionCandidateEvidencePresenter.new(candidate)
      approval_task = approval_required ? board.send(:approval_required_task, candidate) : nil
      direct_reason = board.send(:today_exclusion_reason, candidate, presenter.execution_mode.to_s, approval_task)
      return normalized_exclusion_reason(direct_reason) if direct_reason.present?
      return "duplicate_suppressed" if duplicate_suppressed
      return normalized_exclusion_reason(candidate.metadata.to_h["today_exclusion_reason"]) if candidate_item.blank?
      return "removed_before_ranking" if ranking_input_item.blank?

      classification = TodayRankingClassifier.call(ranking_input_item)
      return classification.exclusion_reason if classification.exclusion_reason.present?

      ranking = ActionExpectedValueRanking.new(items: [ ranking_input_item ], mode: "revenue", per_page: 1)
      return "ranking_guard_rejected" if ranking.send(:excluded_item?, ranking_input_item)

      "not_returned_by_ranking"
    end

    def normalized_exclusion_reason(reason)
      return "already_executed" if reason.to_s == "executed"

      reason.to_s.presence || "not_in_candidate_items"
    end

    def find_candidate_item(items, candidate)
      stable_id = "action_candidate:#{candidate.id}"
      items.find { |item| item.stable_id == stable_id }
    end

    def execution_mode_for(candidate)
      ActionCandidateEvidencePresenter.new(candidate).execution_mode.to_s.presence || candidate.execution_mode
    rescue StandardError
      candidate.execution_mode
    end

    def total_expected_value_yen(candidate)
      board = TodayActionBoard.new(mode: "revenue")
      board.send(:action_candidate_valuation, candidate).fetch(:action_expected_value_delta_yen).to_i
    rescue StandardError
      candidate.final_expected_value_yen.presence || candidate.expected_total_value_yen.presence || candidate.expected_profit_yen.to_i
    end

    def learning_applied?(candidate)
      action_result = candidate.action_result
      return false unless action_result&.evaluation_status == "evaluated"

      ActivityLearningPipelineDiagnostic.new(limit: 1).send(:calibration_for, action_result).present?
    end

    def expected_value_updated?(candidate)
      candidate.action_result&.metadata.to_h.dig("activity_learning_pipeline", "auto_generated") == true
    end

    def missing_result
      modes = TodayActionBoard::MODES.map do |mode|
        ModeResult.new(
          mode:,
          today_eligible: false,
          today_exclusion_reason: "candidate_not_found",
          duplicate_suppressed: false,
          already_executed: false,
          approval_required: false,
          included_in_candidate_items: false,
          included_in_action_candidate_items: false,
          included_in_ranking_input: false,
          included_after_ranking: false,
          included_in_today_board: false,
          display_position: nil,
          final_result: "excluded:candidate_not_found"
        )
      end
      Result.new(
        candidate_id:,
        business_id: nil,
        candidate_exists: false,
        status: nil,
        execution_mode: nil,
        generation_source: nil,
        action_type: nil,
        total_expected_value_yen: nil,
        learning_applied: false,
        expected_value_updated: false,
        today_eligible: false,
        today_exclusion_reason: "candidate_not_found",
        duplicate_suppressed: false,
        already_executed: false,
        approval_required: false,
        included_in_candidate_items: false,
        included_in_action_candidate_items: false,
        included_in_ranking_input: false,
        included_after_ranking: false,
        included_in_today_board: false,
        display_position: nil,
        final_result: "excluded:candidate_not_found",
        modes:
      )
    end
  end
end
