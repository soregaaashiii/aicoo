module Aicoo
  class AnalysisMonitor
    Result = Data.define(
      :generated_at,
      :today_count,
      :pending_count,
      :auto_count,
      :smart_count,
      :manual_count,
      :completed_count,
      :skipped_count,
      :failed_count,
      :estimated_cost_yen,
      :expected_value_yen,
      :roi,
      :top_candidates,
      :warnings
    )

    def initialize(today: Date.current)
      @today = today.to_date
    end

    def call
      Result.new(
        generated_at: Time.current,
        today_count: today_scope.count,
        pending_count: today_scope.where(status: "pending").count,
        auto_count: today_scope.where(execution_mode: "auto").count,
        smart_count: today_scope.where(execution_mode: "smart").count,
        manual_count: today_scope.where(execution_mode: "manual").count,
        completed_count: today_scope.where(status: "completed").count,
        skipped_count: today_scope.where(status: "skipped").count,
        failed_count: today_scope.where(status: "failed").count,
        estimated_cost_yen: today_scope.sum(:estimated_cost_yen),
        expected_value_yen: today_scope.sum(:expected_value_yen),
        roi: ratio(today_scope.sum(:expected_value_yen), today_scope.sum(:estimated_cost_yen)),
        top_candidates: today_scope.includes(:business).ordered.limit(5),
        warnings: warnings
      )
    end

    private

    attr_reader :today

    def today_scope
      @today_scope ||= AnalysisCandidate.where(due_on: today)
    end

    def warnings
      [].tap do |items|
        items << "今日のAnalysis Candidateがまだ生成されていません" if today_scope.none?
        items << "Manual分析候補があります。実行前にコストとROIを確認してください" if today_scope.where(execution_mode: "manual", status: "pending").exists?
        items << "失敗したAnalysis Candidateがあります" if today_scope.where(status: "failed").exists?
      end
    end

    def ratio(numerator, denominator)
      return nil if denominator.to_d.zero?

      numerator.to_d / denominator.to_d
    end
  end
end
