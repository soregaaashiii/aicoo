require "json"

class AiActionReevaluationService
  Result = Data.define(:run, :action_candidate)

  def initialize(action_candidate, client: OpenaiResponsesClient.new)
    @action_candidate = action_candidate
    @business = action_candidate.business
    @client = client
  end

  def call
    response = client.create_json(
      prompt:,
      schema_name: "action_candidate_reevaluation",
      schema: AiActionSchema.reevaluation_schema
    )

    run = nil

    ApplicationRecord.transaction do
      run = create_run(response:)
      action_candidate.update!(AiActionPayload.normalize(response[:parsed].fetch("action")).except(:title, :description, :action_type, :expected_hours, :cost_yen).merge(generation_source: "ai_reevaluation"))
    end

    Result.new(run:, action_candidate:)
  end

  private

  attr_reader :action_candidate, :business, :client

  def input_data
    {
      business: {
        name: business.name,
        description: business.description,
        status: business.status
      },
      action_candidate: {
        title: action_candidate.title,
        description: action_candidate.description,
        action_type: action_candidate.action_type,
        immediate_value_yen: action_candidate.immediate_value_yen,
        success_probability: action_candidate.success_probability,
        strategic_value_score: action_candidate.strategic_value_score,
        risk_reduction_score: action_candidate.risk_reduction_score,
        confidence_score: action_candidate.confidence_score,
        data_confidence_score: action_candidate.data_confidence_score,
        expected_hours: action_candidate.expected_hours,
        cost_yen: action_candidate.cost_yen,
        evaluation_reason: action_candidate.evaluation_reason,
        execution_prompt: action_candidate.execution_prompt
      },
      latest_data_imports: business.data_imports.includes(:data_source).recent.limit(10).map { |data_import| data_import_payload(data_import) }
    }
  end

  def prompt
    @prompt ||= <<~PROMPT
      現在のActionCandidateをAI COOとして再評価してください。

      入力情報:
      #{JSON.pretty_generate(input_data)}

      以下を更新するための値を返してください。
      - immediate_value_yen
      - success_probability
      - strategic_value_score
      - risk_reduction_score
      - confidence_score
      - data_confidence_score
      - evaluation_reason
      - execution_prompt

      title、description、action_type、expected_hours、cost_yen は現在値を維持するため、
      返却JSONには現在値をそのまま含めてください。

      評価は単なるアイデア出しではなく、意思決定支援として行ってください。
      市場規模、困り度、収益性、マーケティングコスト、運営コスト、AI自動化率、初速、
      資本効率、オーナー適性、競合強度を考慮してください。
      SERPデータにcompetition_scoreが含まれる場合は、success_probabilityの重要な材料として使ってください。
      competition_scoreが高いほど上位獲得難度が高く、短期成功確率は慎重に見積もってください。
      data_confidence_score は判断材料の十分さです。
      success_probability は 0.0 から 1.0、各スコアは 0 から 100 です。
    PROMPT
  end

  def data_import_payload(data_import)
    {
      data_source: {
        name: data_import.data_source.name,
        source_type: data_import.data_source.source_type,
        status: data_import.data_source.status,
        notes: data_import.data_source.notes
      },
      filename: data_import.filename,
      content_type: data_import.content_type,
      row_count: data_import.row_count,
      imported_at: data_import.imported_at,
      text: data_import.processed_text.presence || data_import.raw_text.to_s.truncate(20_000)
    }
  end

  def create_run(response:)
    run = business.ai_evaluation_runs.create!(
      input_data: JSON.pretty_generate(input_data),
      prompt:,
      raw_response: response[:raw_response],
      created_action_count: 0
    )
    write_model_name(run, response[:model])
    run
  end

  def write_model_name(run, model_name)
    quoted_model_name = AiEvaluationRun.connection.quote(model_name)
    AiEvaluationRun.connection.execute("UPDATE ai_evaluation_runs SET model_name = #{quoted_model_name} WHERE id = #{run.id.to_i}")
  end
end
