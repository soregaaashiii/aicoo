require "json"
require "uri"

module Aicoo
  class BusinessRegistrationAnalyzer
    DATA_SOURCE_KEYS = DataSourceCostProfile::SOURCE_DEFINITIONS.keys.freeze

    def initialize(business:, prototype: nil, client: OpenaiResponsesClient.new, inspector: nil)
      @business = business
      @prototype = prototype
      @client = client
      @inspector = inspector || (prototype && Aicoo::PrototypeInspector.new(prototype))
    end

    def call
      prototype&.update!(analysis_status: "analyzing")
      evidence = inspection_evidence
      analysis, analysis_source, warning = analyze(evidence)

      ActiveRecord::Base.transaction do
        update_business!(analysis:, evidence:, analysis_source:, warning:)
        update_prototype!(analysis:, evidence:, analysis_source:, warning:) if prototype
        initialize_recommended_sources!(analysis)
        update_initial_candidate!(analysis)
      end

      analysis
    end

    private

    attr_reader :business, :prototype, :client, :inspector

    def inspection_evidence
      return inspector.call if inspector

      {
        "source" => "idea",
        "business_name" => business.name,
        "description" => business.description,
        "inspection_status" => "registered"
      }
    end

    def analyze(evidence)
      response = client.create_json(
        prompt: prompt(evidence),
        schema_name: "business_registration_analysis",
        schema: response_schema
      )
      [ normalize_analysis(response[:parsed], evidence), "openai:#{response[:model]}", nil ]
    rescue OpenaiResponsesClient::MissingApiKeyError, OpenaiResponsesClient::Error => e
      [ fallback_analysis(evidence), "initial_inference", e.message ]
    end

    def normalize_analysis(parsed, evidence)
      fallback = fallback_analysis(evidence)
      result = fallback.merge(parsed.to_h.stringify_keys)
      result["business_type"] = "other" unless result["business_type"].in?(Business::BUSINESS_TYPES)
      result["completion_percentage"] = result["completion_percentage"].to_i.clamp(0, 100)
      result["kpis"] = Array(result["kpis"]).map(&:to_s).compact_blank.first(8).presence || fallback.fetch("kpis")
      sources = Array(result["recommended_data_sources"]).map(&:to_s) & DATA_SOURCE_KEYS
      result["recommended_data_sources"] = sources.presence || fallback.fetch("recommended_data_sources")
      result["today_action"] = fallback.fetch("today_action").merge(result["today_action"].to_h.stringify_keys)
      result
    end

    def fallback_analysis(evidence)
      registration = business.metadata.to_h.fetch("business_registration_v2", {})
      profile = business.metadata.to_h.fetch("business_profile", {})
      mode = registration["mode"].presence || "prototype"
      {
        "business_type" => business.business_type,
        "revenue_model" => profile["revenue_model"].presence || "初期解析後に特定",
        "customer" => profile["customer"].presence || "この課題を持つ見込み顧客",
        "development_status" => profile["development_status"].presence || mode,
        "completion_percentage" => profile["completion_percentage"].to_i,
        "summary" => business.description.presence || evidence["meta_description"].presence || evidence["title"].presence || business.name,
        "kpis" => Array(business.metadata.to_h["kpis"]),
        "recommended_data_sources" => Array(business.metadata.to_h["recommended_data_sources"]),
        "today_action" => {
          "title" => initial_candidate&.title.presence || "#{business.name}の次の実行対象を特定する",
          "description" => initial_candidate&.description.presence || "解析結果から最初に着手する対象を1件決める。"
        }
      }
    end

    def update_business!(analysis:, evidence:, analysis_source:, warning:)
      registration = business.metadata.to_h.fetch("business_registration_v2", {}).merge(
        "analysis_status" => "succeeded",
        "analysis_source" => analysis_source,
        "analyzed_at" => Time.current.iso8601
      )
      registration["analysis_warning"] = warning if warning.present?

      attributes = {
        business_type: analysis.fetch("business_type"),
        metadata: business.metadata.to_h.merge(
          "business_registration_v2" => registration,
          "business_profile" => {
            "revenue_model" => analysis["revenue_model"],
            "customer" => analysis["customer"],
            "development_status" => analysis["development_status"],
            "completion_percentage" => analysis["completion_percentage"],
            "summary" => analysis["summary"]
          },
          "kpis" => analysis.fetch("kpis"),
          "recommended_data_sources" => analysis.fetch("recommended_data_sources"),
          "registration_analysis_evidence" => evidence
        )
      }
      attributes[:description] = analysis["summary"] if business.description.blank? && analysis["summary"].present?
      attributes.merge!(github_business_attributes) if prototype&.prototype_type == "github"
      business.update!(attributes)
    end

    def github_business_attributes
      uri = URI.parse(prototype.location)
      parts = uri.path.to_s.split("/").compact_blank
      repository_name = parts.first(2).join("/").delete_suffix(".git")
      {
        repository_name:,
        project_key: parts.second.to_s.delete_suffix(".git").parameterize.presence
      }.compact
    rescue URI::InvalidURIError
      {}
    end

    def update_prototype!(analysis:, evidence:, analysis_source:, warning:)
      prototype.update!(
        analysis_status: "succeeded",
        analyzed_at: Time.current,
        analysis: {
          "business_type" => analysis["business_type"],
          "revenue_model" => analysis["revenue_model"],
          "customer" => analysis["customer"],
          "development_status" => analysis["development_status"],
          "completion_percentage" => analysis["completion_percentage"],
          "summary" => analysis["summary"],
          "technology_stack" => Array(evidence["technology_signals"]),
          "evidence" => evidence
        },
        metadata: prototype.metadata.to_h.merge(
          "analysis_source" => analysis_source,
          "analysis_warning" => warning,
          "analyzed_at" => Time.current.iso8601
        ).compact
      )
    end

    def initialize_recommended_sources!(analysis)
      Array(analysis["recommended_data_sources"]).each do |source_key|
        next unless source_key.in?(DATA_SOURCE_KEYS)

        setting = business.business_data_source_settings.find_or_initialize_by(source_key:)
        setting.assign_attributes(
          enabled: true,
          metadata: setting.metadata.to_h.merge(
            "recommended" => true,
            "recommended_by" => "business_registration_analysis"
          )
        )
        setting.save!
      end
    end

    def update_initial_candidate!(analysis)
      candidate = initial_candidate
      return unless candidate

      today_action = analysis.fetch("today_action", {})
      candidate.update!(
        title: today_action["title"].presence || candidate.title,
        description: today_action["description"].presence || candidate.description,
        metadata: candidate.metadata.to_h.merge(
          "analysis_completed" => true,
          "analysis_completed_at" => Time.current.iso8601,
          "business_type" => analysis["business_type"],
          "revenue_model" => analysis["revenue_model"],
          "target_customer" => analysis["customer"],
          "next_action" => today_action["description"].presence || candidate.metadata.to_h["next_action"]
        )
      )
    end

    def initial_candidate
      @initial_candidate ||= business.action_candidates.find_by(
        generation_source: "business_registration",
        status: %w[idea proposal planning pending]
      )
    end

    def prompt(evidence)
      <<~PROMPT
        AICOOへ新しく登録された事業を解析してください。SERPや市場データを新たに検索せず、登録情報と取得済みのプロトタイプ情報だけを使います。

        Business:
        #{JSON.pretty_generate({ name: business.name, description: business.description, current_business_type: business.business_type })}

        Prototype evidence:
        #{JSON.pretty_generate(evidence)}

        次を簡潔に推定してください。
        - Business Type
        - Revenue Model
        - Customer
        - 開発状況と完成度
        - KPI
        - 推奨データソース
        - 今日最初に行う、対象特定またはデータ準備の作業1件

        根拠のない具体的な売上や市場規模は作らないでください。今日の作業はCodex自動改修ではなく、安全な準備作業にしてください。
      PROMPT
    end

    def response_schema
      {
        type: "object",
        additionalProperties: false,
        required: %w[business_type revenue_model customer development_status completion_percentage summary kpis recommended_data_sources today_action],
        properties: {
          business_type: { type: "string", enum: Business::BUSINESS_TYPES },
          revenue_model: { type: "string" },
          customer: { type: "string" },
          development_status: { type: "string" },
          completion_percentage: { type: "integer", minimum: 0, maximum: 100 },
          summary: { type: "string" },
          kpis: { type: "array", items: { type: "string" }, maxItems: 8 },
          recommended_data_sources: { type: "array", items: { type: "string", enum: DATA_SOURCE_KEYS }, maxItems: 8 },
          today_action: {
            type: "object",
            additionalProperties: false,
            required: %w[title description],
            properties: {
              title: { type: "string" },
              description: { type: "string" }
            }
          }
        }
      }
    end
  end
end
