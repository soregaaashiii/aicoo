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
    OwnerHomeResult = Data.define(
      :today_count,
      :auto_count,
      :smart_count,
      :manual_count,
      :estimated_cost_yen,
      :expected_value_yen,
      :top_candidates
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

    def call_for_owner_home
      aggregate = today_scope.pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(CASE WHEN execution_mode = 'auto' THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN execution_mode = 'smart' THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN execution_mode = 'manual' THEN 1 ELSE 0 END)"),
        Arel.sql("COALESCE(SUM(estimated_cost_yen), 0)"),
        Arel.sql("COALESCE(SUM(expected_value_yen), 0)")
      )

      OwnerHomeResult.new(
        today_count: aggregate[0].to_i,
        auto_count: aggregate[1].to_i,
        smart_count: aggregate[2].to_i,
        manual_count: aggregate[3].to_i,
        estimated_cost_yen: aggregate[4],
        expected_value_yen: aggregate[5],
        top_candidates: today_scope.includes(:business).ordered.limit(5).to_a
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
