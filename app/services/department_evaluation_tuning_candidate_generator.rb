class DepartmentEvaluationTuningCandidateGenerator
  Result = Data.define(:created, :skipped)

  MIN_ABSOLUTE_GAP_YEN = 10_000
  MIN_RELATIVE_GAP = 0.3.to_d
  MIN_EVALUATED_COUNT = 1
  LOW_SUCCESS_RATE = 0.5.to_d

  def initialize(summary_service: ActionResultDepartmentSummary.new)
    @summary_service = summary_service
    @created = []
    @skipped = []
  end

  def call
    summary_service.summaries.each do |summary|
      spec = spec_for(summary)
      if spec
        create_candidate(summary, spec)
      else
        skipped << "#{summary.department}: no tuning needed"
      end
    end

    Result.new(created:, skipped:)
  end

  private

  attr_reader :summary_service, :created, :skipped

  TuningSpec = Data.define(:title, :reason, :prompt)

  def spec_for(summary)
    return if summary.executed_count < MIN_EVALUATED_COUNT

    case summary.department
    when "revenue"
      revenue_spec(summary)
    when "lab"
      lab_spec(summary)
    when "new_business"
      new_business_spec(summary)
    end
  end

  def revenue_spec(summary)
    return unless underperformed?(summary)

    TuningSpec.new(
      title: "Revenue評価式の成功確率を保守的に補正する",
      reason: "Revenue部門の実績利益が予測を大きく下回っています。",
      prompt: "Revenue部門のActionResultを確認し、成功確率・期待利益・ROIの見積もりが過大になっていないか点検してください。特にGSC/GA4/SERP由来の候補で、実績が予測を下回った理由を整理し、成功確率を保守的にするルール案を作ってください。"
    )
  end

  def lab_spec(summary)
    return unless summary.success_rate && summary.success_rate < LOW_SUCCESS_RATE

    TuningSpec.new(
      title: "Labの学習価値スコアの重みを見直す",
      reason: "Lab部門の成功率が低く、学習価値の見積もりが実行結果に結びついていない可能性があります。",
      prompt: "Lab部門のActionResultを確認し、学習価値・データ信頼度・低コスト実験の重みが適切か点検してください。成功率が低い候補の共通点を整理し、学習価値スコアの重み見直し案を作ってください。"
    )
  end

  def new_business_spec(summary)
    return unless large_gap?(summary)

    TuningSpec.new(
      title: "新規事業評価の市場規模・自動化率を再点検する",
      reason: "新規事業部門の予測誤差が大きく、市場規模や自動化率を過大評価している可能性があります。",
      prompt: "新規事業部門のActionResultを確認し、市場規模・自動化率・初速の見積もりが過大になっていないか点検してください。MVP、市場調査、新規LPの実績差分を見て、評価式の警告条件を提案してください。"
    )
  end

  def create_candidate(summary, spec)
    business = representative_business(summary.department)
    unless business
      skipped << "#{summary.department}: representative business missing"
      return
    end

    if duplicate?(business, summary.department, spec.title)
      skipped << "#{summary.department}: duplicate"
      return
    end

    created << business.action_candidates.create!(
      title: spec.title,
      description: spec.reason,
      action_type: "evaluation_tuning",
      department: "lab",
      generation_source: "ai_reevaluation",
      immediate_value_yen: 0,
      success_probability: 0.7,
      strategic_value_score: 80,
      risk_reduction_score: 70,
      confidence_score: 60,
      data_confidence_score: summary.average_confidence_score.to_i,
      expected_hours: 1,
      cost_yen: 0,
      status: "idea",
      metadata: {
        "metric_rule" => "department_evaluation_tuning",
        "target_department" => summary.department,
        "prediction_gap_yen" => summary.prediction_gap_yen,
        "success_rate" => summary.success_rate&.to_f,
        "executed_count" => summary.executed_count
      },
      evaluation_reason: "department_evaluation_tuning:#{summary.department}\n#{spec.reason}\n予測との差: #{summary.prediction_gap_yen}円 / 成功率: #{summary.success_rate || 'データ不足'}",
      execution_prompt: spec.prompt
    )
  end

  def underperformed?(summary)
    summary.prediction_gap_yen.to_i <= -MIN_ABSOLUTE_GAP_YEN || relative_gap(summary) <= -MIN_RELATIVE_GAP
  end

  def large_gap?(summary)
    summary.prediction_gap_yen.to_i.abs >= MIN_ABSOLUTE_GAP_YEN || relative_gap(summary).abs >= MIN_RELATIVE_GAP
  end

  def relative_gap(summary)
    predicted = summary.predicted_expected_profit_total_yen.to_i
    return 0.to_d if predicted.zero?

    summary.prediction_gap_yen.to_d / predicted
  end

  def representative_business(department)
    records_for(department).max_by { |record| record.prediction_error_yen.to_i }&.business ||
      Business.real_businesses.order(:name).first
  end

  def records_for(department)
    @records_by_department ||= ActionResult.includes(:business, :action_candidate)
                                           .where(evaluation_status: "evaluated")
                                           .to_a
                                           .group_by { |record| record.action_candidate&.department }
    @records_by_department.fetch(department, [])
  end

  def duplicate?(business, department, title)
    business.action_candidates
            .where(action_type: "evaluation_tuning", created_at: 7.days.ago..)
            .where("title = ? OR metadata ->> 'target_department' = ?", title, department)
            .exists?
  end
end
