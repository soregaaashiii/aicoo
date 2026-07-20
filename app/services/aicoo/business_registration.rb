require "uri"

module Aicoo
  class BusinessRegistration
    MODES = %w[idea prototype published_service].freeze
    PROTOTYPE_TYPES = BusinessPrototype::PROTOTYPE_TYPES

    Result = Data.define(:business, :prototype, :action_candidates)

    class InvalidRegistration < StandardError; end

    def initialize(mode:, name: nil, description: nil, prototype_type: nil, prototype_location: nil)
      @mode = mode.to_s
      @name = name.to_s.squish
      @description = description.to_s.squish
      @prototype_type = prototype_type.to_s
      @prototype_location = prototype_location.to_s.strip
    end

    def call
      validate!
      result = nil

      ActiveRecord::Base.transaction do
        business = Business.create!(business_attributes)
        prototype = create_prototype(business)
        initialize_data_sources!(business)
        candidates = create_initial_candidates!(business, prototype)
        result = Result.new(business:, prototype:, action_candidates: candidates)
      end

      Aicoo::BusinessRegistrationAnalysisJob.perform_later(result.business.id, result.prototype&.id)
      result
    end

    private

    attr_reader :mode, :name, :description, :prototype_type, :prototype_location

    def validate!
      raise InvalidRegistration, "登録方法を選択してください" unless mode.in?(MODES)
      raise InvalidRegistration, "事業名を入力してください" if mode != "published_service" && name.blank?
      raise InvalidRegistration, "事業概要を入力してください" if mode == "idea" && description.blank?
      return if mode == "idea"

      raise InvalidRegistration, "プロトタイプ種別を選択してください" if mode == "prototype" && !prototype_type.in?(PROTOTYPE_TYPES)
      raise InvalidRegistration, "URLまたは保存場所を入力してください" if prototype_location.blank?
    end

    def business_attributes
      defaults = inferred_defaults
      {
        name: resolved_name,
        description: description.presence || defaults.fetch("summary"),
        status: mode == "published_service" ? "launched" : (mode == "prototype" ? "building" : "idea"),
        lifecycle_stage: mode == "published_service" ? "production" : (mode == "prototype" ? "mvp" : "idea"),
        business_type: defaults.fetch("business_type"),
        source: "business_registration_v2",
        created_by_aicoo: false,
        launched: mode == "published_service",
        metadata: {
          "business_registration_v2" => {
            "mode" => mode,
            "registered_at" => Time.current.iso8601,
            "analysis_status" => "queued",
            "analysis_source" => "initial_inference"
          },
          "business_profile" => defaults.slice("revenue_model", "customer", "development_status", "completion_percentage"),
          "kpis" => defaults.fetch("kpis"),
          "recommended_data_sources" => recommended_data_sources,
          "initial_settings" => {
            "auto_revision_mode" => "manual",
            "auto_deploy_mode" => "manual",
            "daily_run_enabled" => true
          }
        }
      }
    end

    def resolved_name
      return name if name.present?

      uri = URI.parse(prototype_location)
      uri.host.to_s.sub(/\Awww\./, "").presence || "新しい公開サービス"
    rescue URI::InvalidURIError
      "新しい公開サービス"
    end

    def create_prototype(business)
      return if mode == "idea"

      type = mode == "published_service" ? "url" : prototype_type
      business.business_prototypes.create!(
        prototype_type: type,
        location: prototype_location,
        analysis_status: "queued",
        metadata: {
          "registration_mode" => mode,
          "primary" => true,
          "registered_at" => Time.current.iso8601
        }
      )
    end

    def initialize_data_sources!(business)
      DataSourceCostProfile.ensure_defaults!
      recommended_data_sources.each do |source_key|
        business.business_data_source_settings.create!(
          source_key:,
          enabled: true,
          connection_status: "unlinked",
          metadata: {
            "recommended" => true,
            "recommended_by" => "business_registration_v2",
            "registration_mode" => mode
          }
        )
      end
    end

    def create_initial_candidates!(business, prototype)
      [ business.action_candidates.create!(
        title: initial_action_title,
        description: initial_action_description,
        action_type: "data_preparation",
        status: "proposal",
        generation_source: "business_registration",
        success_probability: 0.8,
        expected_hours: 0.5,
        immediate_value_yen: DataSourceCostProfile.for_source("opportunity_scan").average_expected_profit_yen.to_i,
        confidence_score: 40,
        data_confidence_score: 30,
        evaluation_reason: "Business Registration v2の初期解析結果を確定し、次の実行候補へつなげます。",
        metadata: {
          "registration_mode" => mode,
          "business_prototype_id" => prototype&.id,
          "initial_candidate" => true,
          "execution_readiness" => "needs_target",
          "codex_eligible" => false,
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false,
          "next_action" => initial_action_description
        }
      ) ]
    end

    def initial_action_title
      case mode
      when "idea" then "#{resolved_name}の顧客仮説と最初の検証対象を特定する"
      when "published_service" then "#{resolved_name}の公開状況と最初の改善対象を特定する"
      else "#{resolved_name}のプロトタイプを解析し、次の開発対象を特定する"
      end
    end

    def initial_action_description
      case mode
      when "idea" then "顧客、課題、収益モデル、検証KPIを整理し、最初に検証する仮説を1件決める。"
      when "published_service" then "公開ページ、計測状況、主要CTAを解析し、最初に改善する対象を1件決める。"
      else "技術構成と完成度を解析し、公開までに必要な次の作業を1件決める。"
      end
    end

    def inferred_defaults
      @inferred_defaults ||= begin
        corpus = [ name, description, prototype_location ].join(" ").downcase
        business_type = if corpus.match?(/saas|月額|subscription|業務支援|ai/)
          "saas"
        elsif corpus.match?(/メディア|記事|seo|比較|検索/)
          "content_media"
        elsif mode == "published_service"
          "mvp"
        elsif mode == "prototype"
          "mvp"
        else
          "other"
        end

        {
          "business_type" => business_type,
          "revenue_model" => corpus.match?(/月額|subscription|saas/) ? "月額課金" : "初期検証で課金・送客・成果報酬から特定",
          "customer" => customer_from_description,
          "development_status" => mode == "idea" ? "idea" : (mode == "prototype" ? "prototype" : "published"),
          "completion_percentage" => mode == "idea" ? 10 : (mode == "prototype" ? 45 : 80),
          "summary" => description.presence || "#{resolved_name}をAICOOで解析・改善する事業です。",
          "kpis" => default_kpis
        }
      end
    end

    def customer_from_description
      text = description.presence || resolved_name
      matched = text.match(/([^。、]{2,30})(?:向け|が使う|のための)/)&.captures&.first
      matched.presence || "この課題を持つ見込み顧客"
    end

    def default_kpis
      case mode
      when "idea" then %w[顧客ヒアリング数 仮説検証数 初回コンバージョン]
      when "published_service" then %w[セッション CTAクリック CV CVR 売上]
      else %w[実装完了率 公開準備項目数 初回利用数]
      end
    end

    def recommended_data_sources
      @recommended_data_sources ||= case mode
      when "idea" then %w[explore opportunity_scan learning]
      when "published_service" then %w[ga4 gsc revenue business_metric_daily]
      else
        base = %w[ga4 gsc business_metric_daily]
        prototype_type == "github" ? [ "github", *base ] : base
      end
    end
  end
end
