require "json"

class AiActionGeneratorService
  Result = Data.define(:run, :action_candidates)

  def initialize(business, action_count: 5, client: OpenaiResponsesClient.new)
    @business = business
    @action_count = [ 3, 5, 10 ].include?(action_count.to_i) ? action_count.to_i : 5
    @client = client
  end

  def call
    return Result.new(run: nil, action_candidates: []) if business.action_candidate_generation_blocked?

    response = client.create_json(
      prompt:,
      schema_name: "action_candidate_generation",
      schema: AiActionSchema.actions_schema(action_count:)
    )

    action_candidates = []
    run = nil

    ApplicationRecord.transaction do
      run = create_run(response:, created_action_count: 0)
      action_candidates = response[:parsed].fetch("actions").first(action_count).filter_map do |attributes|
        normalized = AiActionPayload.normalize(attributes)
        decision = business.business_type_playbook.call(normalized)
        next unless decision.allowed

        business.action_candidates.create!(
          normalized.merge(
            status: "idea",
            generation_source: "ai_business",
            priority_score: 0,
            metadata: { "business_type_playbook" => decision.metadata }
          )
        )
      end
      run.update!(created_action_count: action_candidates.size)
    end

    Result.new(run:, action_candidates:)
  end

  private

  attr_reader :business, :action_count, :client

  def input_data
    {
      business: {
        name: business.name,
        description: business.description,
        status: business.status,
        business_type: business.business_type,
        allowed_actions: business.business_type_playbook.allowed_actions,
        preferred_actions: business.business_type_playbook.preferred_actions,
        forbidden_actions: business.business_type_playbook.forbidden_actions
      },
      latest_data_imports: latest_data_imports.map { |data_import| data_import_payload(data_import) }
    }
  end

  def prompt
    @prompt ||= <<~PROMPT
      あなたはAI COOです。
      入力された事業データを分析し、期待利益最大化のために今やるべき行動候補を#{action_count}件生成してください。

      入力情報:
      #{JSON.pretty_generate(input_data)}

      各候補について以下を推定してください。
      - title
      - description
      - action_type
      - immediate_value_yen
      - success_probability
      - strategic_value_score
      - risk_reduction_score
      - confidence_score
      - data_confidence_score
      - expected_hours
      - cost_yen
      - evaluation_reason
      - execution_prompt

      評価は単なるアイデア出しではなく、意思決定支援として行ってください。
      business_typeのallowed_actionsに含まれるaction_typeだけを生成してください。
      preferred_actionsに含まれる改善は優先し、forbidden_actionsに含まれる改善は絶対に生成しないでください。
      GSC、GA4、SERP、市場規模、困り度、競合強度、収益性、マーケティングコスト、
      運営コスト、AI自動化率、初速、資本効率、オーナー適性を考慮してください。
      SERPデータにcompetition_scoreが含まれる場合は、success_probabilityの重要な材料として使ってください。
      competition_scoreが高いほど上位獲得難度が高く、短期成功確率は慎重に見積もってください。
      data_confidence_score は判断材料の十分さです。Business説明だけなら20程度、
      GSC + GA4 + SERP が揃っていれば90程度を目安にしてください。
      success_probability は 0.0 から 1.0、各スコアは 0 から 100 です。
    PROMPT
  end

  def latest_data_imports
    @latest_data_imports ||= business.data_imports.includes(:data_source).recent.limit(10)
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

  def create_run(response:, created_action_count:)
    run = business.ai_evaluation_runs.create!(
      input_data: JSON.pretty_generate(input_data),
      prompt:,
      raw_response: response[:raw_response],
      created_action_count:
    )
    write_model_name(run, response[:model])
    run
  end

  def write_model_name(run, model_name)
    quoted_model_name = AiEvaluationRun.connection.quote(model_name)
    AiEvaluationRun.connection.execute("UPDATE ai_evaluation_runs SET model_name = #{quoted_model_name} WHERE id = #{run.id.to_i}")
  end
end
