require "json"

class AiCrossBusinessTopActionsService
  Result = Data.define(:runs, :action_candidates)
  ACTION_COUNT = 10

  def initialize(client: OpenaiResponsesClient.new)
    @client = client
  end

  def call
    response = client.create_json(
      prompt:,
      schema_name: "cross_business_top_actions",
      schema: AiActionSchema.cross_business_actions_schema(action_count: ACTION_COUNT)
    )

    action_candidates = []
    runs = []

    ApplicationRecord.transaction do
      action_candidates = response[:parsed].fetch("actions").first(ACTION_COUNT).filter_map do |attributes|
        business = businesses_by_id[attributes.fetch("business_id").to_i]
        next unless business

        business.action_candidates.create!(AiActionPayload.normalize(attributes).merge(status: "idea", generation_source: "ai_cross_business", priority_score: 0))
      end
      runs = create_runs(response:, action_candidates:)
    end

    Result.new(runs:, action_candidates:)
  end

  private

  attr_reader :client

  def businesses
    @businesses ||= Business.includes(:data_imports, :serp_analyses, :action_candidates).order(:name).to_a
  end

  def businesses_by_id
    @businesses_by_id ||= businesses.index_by(&:id)
  end

  def input_data
    {
      instruction: "Generate action-level priorities across all businesses. Do not choose a business; choose concrete actions.",
      businesses: businesses.map { |business| business_payload(business) },
      existing_top_unfinished_action_candidates: existing_unfinished_actions
    }
  end

  def business_payload(business)
    {
      id: business.id,
      name: business.name,
      description: business.description,
      status: business.status,
      latest_data_imports: business.data_imports.sort_by { |data_import| data_import.imported_at || Time.zone.at(0) }.reverse.first(5).map do |data_import|
        data_import_payload(data_import)
      end,
      latest_serp_analyses: business.serp_analyses.sort_by { |analysis| analysis.analyzed_at || Time.zone.at(0) }.reverse.first(5).map do |analysis|
        serp_analysis_payload(analysis)
      end
    }
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

  def serp_analysis_payload(analysis)
    {
      keyword: analysis.keyword,
      search_engine: analysis.search_engine,
      location: analysis.location,
      device: analysis.device,
      result_count: analysis.result_count,
      competition_score: analysis.competition_score,
      summary: analysis.summary,
      analyzed_at: analysis.analyzed_at
    }
  end

  def existing_unfinished_actions
    ActionCandidate.includes(:business)
                   .where.not(status: %w[done rejected archived])
                   .by_recommendation
                   .limit(30)
                   .map do |action|
      {
        id: action.id,
        business_id: action.business_id,
        business_name: action.business.name,
        title: action.title,
        action_type: action.action_type,
        expected_profit_yen: action.expected_profit_yen,
        expected_hourly_value_yen: action.expected_hourly_value_yen,
        final_score: action.final_score,
        status: action.status,
        evaluation_reason: action.evaluation_reason
      }
    end
  end

  def prompt
    @prompt ||= <<~PROMPT
      あなたはAI COOです。
      全Businessの情報、最新DataImport、最新SerpAnalysis、既存未完了ActionCandidateを横断的に分析し、
      「今やるべきActionCandidate TOP10」を最大10件生成してください。

      入力情報:
      #{JSON.pretty_generate(input_data)}

      最重要ルール:
      - 事業を選ぶのではなく、行動を選んでください。
      - NG: 吸えログを優先
      - OK: 吸えログで梅田喫煙居酒屋記事の内部リンクを改善する
      - NG: 名刺共有アプリを進める
      - OK: 名刺共有アプリで管理者権限UIを改善する
      - それぞれの出力には必ず対象Businessのbusiness_idを含めてください。

      判断基準:
      - 短期期待値ランキング: expected_hourly_value_yen と expected_profit_yenを意識する
      - 分散込みランキング: strategic_value_score, risk_reduction_score, data_confidence_scoreを意識する
      - GSC、GA4、SERP、既存ActionCandidateのスコアと理由を材料にする
      - SERPのcompetition_scoreが高い場合、SEO系ActionCandidateのsuccess_probabilityは慎重に見積もる
      - 既存ActionCandidateと重複するだけの提案は避け、重複する場合はより具体的な次アクションに分解する

      各候補について以下を推定してください。
      - business_id
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

      success_probability は 0.0 から 1.0、各スコアは 0 から 100 です。
    PROMPT
  end

  def create_runs(response:, action_candidates:)
    action_candidates.group_by(&:business).map do |business, candidates|
      run = business.ai_evaluation_runs.create!(
        input_data: JSON.pretty_generate(input_data),
        prompt:,
        raw_response: response[:raw_response],
        created_action_count: candidates.size
      )
      write_model_name(run, response[:model])
      run
    end
  end

  def write_model_name(run, model_name)
    quoted_model_name = AiEvaluationRun.connection.quote(model_name)
    AiEvaluationRun.connection.execute("UPDATE ai_evaluation_runs SET model_name = #{quoted_model_name} WHERE id = #{run.id.to_i}")
  end
end
