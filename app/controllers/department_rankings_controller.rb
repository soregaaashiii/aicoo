class DepartmentRankingsController < ApplicationController
  def index
    @department_ranking = ActionCandidateDepartmentRanking.new(active_department: params[:department], limit: 50).call
    @department_precision_summaries = ActionResultDepartmentSummary.new.summaries
  end

  def classify
    result = ActionCandidateDepartmentClassifierService.new(overwrite: params[:mode] == "all").call
    redirect_to department_rankings_path, notice: classify_message(result)
  end

  def generate_evaluation_tuning
    result = DepartmentEvaluationTuningCandidateGenerator.new.call
    redirect_to department_rankings_path, notice: "評価式改善候補を#{result.created.size}件生成しました。スキップ: #{result.skipped.size}件"
  end

  private

  def classify_message(result)
    counts = result.counts
    "department一括分類を実行しました。更新 #{result.updated_count}件 / revenue #{counts.fetch('revenue')}件 / lab #{counts.fetch('lab')}件 / new_business #{counts.fetch('new_business')}件 / general #{counts.fetch('general')}件"
  end
end
