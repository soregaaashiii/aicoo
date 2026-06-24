module Aicoo
  class ActionResultDraftBuilder
    def initialize(action_execution)
      @action_execution = action_execution
    end

    def call
      ActionResult.new(
        action_execution:,
        action_candidate: action_execution.action_candidate,
        business: action_execution.business,
        executed_on: action_execution.started_at&.to_date || action_execution.completed_at&.to_date || Date.current,
        evaluated_on: Date.current,
        predicted_value_yen: action_execution.predicted_profit_yen_snapshot.to_i,
        predicted_success_probability: action_execution.predicted_success_probability_snapshot,
        predicted_expected_profit_yen: action_execution.predicted_profit_yen_snapshot.to_i,
        actual_profit_yen: 0,
        actual_revenue_yen: 0,
        evaluation_status: "pending",
        note: draft_note
      )
    end

    private

    attr_reader :action_execution

    def draft_note
      [
        "ActionExecution ##{action_execution.id} からDraft作成",
        "予測時間: #{action_execution.predicted_hours_snapshot || '-'}h",
        "実績時間: #{action_execution.actual_hours || '-'}h",
        "予測コスト: #{action_execution.predicted_cost_yen_snapshot.to_i}円",
        "実績コスト: #{action_execution.actual_cost_yen.to_i}円",
        "score: #{action_execution.action_score_snapshot || '-'}",
        action_execution.result_summary.presence
      ].compact.join("\n")
    end
  end
end
