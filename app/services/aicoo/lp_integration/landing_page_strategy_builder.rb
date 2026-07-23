require "json"

module Aicoo
  module LpIntegration
    class LandingPageStrategyBuilder
      PURPOSES = {
        "seo" => "SEO",
        "google_ads" => "Google広告",
        "meta_ads" => "Meta広告",
        "comparison" => "比較",
        "regional" => "地域",
        "sns" => "SNS",
        "email" => "メール",
        "other" => "その他"
      }.freeze

      DEFAULT_STRUCTURES = {
        "comparison" => [ "ファーストビュー", "比較条件", "比較表", "選ばれる理由", "導入の流れ", "FAQ", "最終CTA" ],
        "regional" => [ "地域名を含むファーストビュー", "地域固有の課題", "対応内容", "利用事例", "料金・流れ", "FAQ", "最終CTA" ]
      }.freeze
      STANDARD_STRUCTURE = [ "ファーストビュー", "顧客の課題", "提供価値", "特徴・根拠", "利用の流れ", "FAQ", "最終CTA" ].freeze
      ESTIMATED_WORK_HOURS = {
        "seo" => 3.0, "google_ads" => 2.5, "meta_ads" => 2.5, "comparison" => 3.5,
        "regional" => 2.5, "sns" => 2.0, "email" => 2.0, "other" => 3.0
      }.freeze

      def initialize(business:, campaign:, purpose:, notes: nil, advanced: {}, client: OpenaiResponsesClient.new)
        @business = business
        @campaign = campaign
        @purpose = purpose.to_s
        @notes = notes.to_s
        @advanced = advanced.to_h.deep_stringify_keys
        @client = client
      end

      def call
        raise ArgumentError, "作成目的を選択してください。" unless purpose.in?(PURPOSES)

        fallback = fallback_strategy
        response = client.create_json(prompt: prompt, schema_name: "aicoo_landing_page_strategy", schema: response_schema)
        normalize(fallback.merge(response.fetch(:parsed).to_h.deep_stringify_keys)).merge(
          "analysis_source" => "openai:#{response[:model]}",
          "analysis_warning" => nil,
          "evidence" => evidence
        )
      rescue OpenaiResponsesClient::MissingApiKeyError, OpenaiResponsesClient::Error => e
        normalize(fallback_strategy).merge(
          "analysis_source" => "existing_data_fallback",
          "analysis_warning" => e.message,
          "evidence" => evidence
        )
      end

      private

      attr_reader :business, :campaign, :purpose, :notes, :advanced, :client

      def evidence
        @evidence ||= {
          "business" => {
            "name" => business.name,
            "description" => business.description,
            "type" => business.business_type,
            "profile" => business.metadata.to_h["business_profile"]
          },
          "service" => business.business_services.recent.limit(5).map { |service|
            { "name" => service.name, "framework" => service.metadata.to_h["framework"], "url" => service.url }
          },
          "campaign" => {
            "name" => campaign.name,
            "type" => campaign.campaign_type,
            "ga4_filter" => campaign.ga4_filter,
            "gsc_filter" => campaign.gsc_filter,
            "target_conversions" => campaign.target_conversions,
            "target_cpa_yen" => campaign.target_cpa_yen
          },
          "purpose" => PURPOSES.fetch(purpose),
          "notes" => notes.presence,
          "existing_landing_pages" => existing_landing_page_evidence,
          "search_queries" => search_query_evidence,
          "competitors" => Array(business.metadata.to_h["competitors"]),
          "improvement_history" => business.action_candidates.where(generation_source: "lp_learning").order(created_at: :desc).limit(20).map { |candidate|
            { "title" => candidate.title, "reason" => candidate.evaluation_reason, "expected_profit_yen" => candidate.final_expected_value_yen }
          },
          "recent_activity" => business.business_activity_logs.recent.limit(50).pluck(:activity_type).tally,
          "measurement" => {
            "ga4_connected" => AicooAnalyticsSite.where(business:).where.not(ga4_property_id: [ nil, "" ]).exists?,
            "gsc_connected" => AicooAnalyticsSite.where(business:).where.not(gsc_site_url: [ nil, "" ]).exists?,
            "activity_api_connected" => business.source_app_connections.active.exists?
          },
          "advanced_overrides" => advanced.compact_blank
        }.compact
      end

      def prompt
        <<~PROMPT
          AICOOのLP戦略担当として、保存済みのBusiness・Service・Campaign・既存LP・計測情報だけを使い、新しいLPの制作戦略を作成してください。

          入力:
          #{JSON.pretty_generate(evidence)}

          人間が指定したのは作成目的と任意の補足だけです。キーワード、検索意図、ターゲット、ペルソナ、USP、見出し、CTA、FAQ、比較表、構成、SEO、画像、カラー方針はAICOOが決定してください。
          advanced_overridesに値がある項目だけは固定条件として尊重してください。根拠のないアクセス数・売上・CVは作らないでください。
          公開はLovableでは行わず、Ownerレビュー後にGitHubとCloudflare Pagesへ進む前提にしてください。
        PROMPT
      end

      def existing_landing_page_evidence
        campaign.landing_pages.active.limit(20).map do |lp|
          metadata = lp.metadata.to_h
          analytics = Aicoo::Lovable::LandingPageAnalyticsReader.new(
            business:,
            started_at: 90.days.ago,
            ended_at: Time.current,
            target_paths: [ lp.landing_page_ga4_path, lp.landing_page_url ],
            snapshots: analytics_snapshots
          ).call
          {
            "name" => lp.landing_page_name,
            "status" => lp.landing_page_public_status,
            "cta" => metadata["cta"],
            "conversion_rate" => metadata["current_conversion_rate"],
            "expected_profit_yen" => metadata["expected_profit_yen"],
            "ga4" => analytics.ga4,
            "gsc" => analytics.gsc,
            "improvement_status" => metadata["improvement_status"]
          }
        end
      end

      def search_query_evidence
        stored = business.business_serp_keywords.order(priority_score: :desc).limit(20).pluck(:keyword)
        snapshot = analytics_snapshots["gsc"]
        rows = Array(snapshot&.payload.to_h&.dig("rows") || snapshot&.payload.to_h&.dig("metrics", "rows"))
        measured = rows.filter_map do |row|
          values = row.to_h.deep_stringify_keys
          query = values["query"].presence || values["keyword"].presence
          next if query.blank?

          [ query, values["impressions"].to_i ]
        end.sort_by { |_query, impressions| -impressions }.map(&:first)
        (measured + stored).uniq.first(20)
      end

      def analytics_snapshots
        @analytics_snapshots ||= Aicoo::Lovable::LandingPageAnalyticsReader.latest_snapshots_for(business)
      end

      def fallback_strategy
        label = PURPOSES.fetch(purpose)
        keywords = fixed_keywords.presence || observed_keywords
        target = advanced["persona"].presence || business.metadata.to_h.dig("business_profile", "customer").presence || "#{business.name}の利用を検討している顧客"
        cta = advanced["cta"].presence || business.metadata.to_h["cta"].presence || "相談する"
        title = [ business.name, label ].compact_blank.join(" | ")
        expected = expected_value_estimate
        {
          "purpose_label" => label,
          "keywords" => keywords,
          "search_intent" => search_intent(label),
          "target" => target,
          "persona" => target,
          "usp" => business.metadata.to_h["usp"].presence || business.description.presence || business.name,
          "headline" => "#{business.name}で#{purpose_outcome(label)}",
          "subheadline" => notes.presence || business.description.presence || "必要な情報と次の行動を一つのページで案内します。",
          "cta" => cta,
          "faq" => [ "どのような人が対象ですか？", "利用開始までの流れは？", "料金や相談方法は？" ],
          "comparison_table" => purpose == "comparison" ? [ "機能", "料金", "導入時間", "サポート" ] : [],
          "structure" => DEFAULT_STRUCTURES.fetch(purpose, STANDARD_STRUCTURE),
          "seo_title" => advanced["seo_title"].presence || title,
          "meta_description" => "#{business.name}の#{label}向けLPです。#{business.description.to_s.truncate(90)}",
          "image_instructions" => Array(advanced["image_instructions"]).presence || [ "サービスの実体や利用場面が分かる画像を優先する" ],
          "color_direction" => advanced["brand_colors"].presence || business.metadata.to_h["brand_colors"].presence || "既存ブランドとサービス内容に合わせる",
          "design_direction" => advanced["design_direction"].presence || "目的達成に必要な情報を短く比較でき、主CTAが明確なレスポンシブLP",
          "expected_profit_yen" => expected.fetch("expected_profit_yen"),
          "expected_cv" => expected.fetch("expected_cv"),
          "expected_hourly_value_yen" => expected.fetch("expected_hourly_value_yen"),
          "estimated_work_hours" => expected.fetch("estimated_work_hours"),
          "expected_value_source" => expected.fetch("source"),
          "confidence" => confidence,
          "reason" => strategy_reason(keywords)
        }
      end

      def normalize(value)
        fallback = fallback_strategy
        result = fallback.merge(value.to_h.deep_stringify_keys)
        %w[keywords faq comparison_table structure image_instructions].each do |key|
          result[key] = Array(result[key]).map(&:to_s).compact_blank.first(20)
        end
        %w[search_intent target persona usp headline subheadline cta seo_title meta_description color_direction design_direction reason].each do |key|
          result[key] = result[key].to_s.strip.presence || fallback.fetch(key)
        end
        result.slice(
          *response_properties.keys,
          "purpose_label",
          "expected_profit_yen",
          "expected_cv",
          "expected_hourly_value_yen",
          "estimated_work_hours",
          "expected_value_source",
          "confidence",
          "analysis_source",
          "analysis_warning",
          "evidence"
        )
      end

      def expected_value_estimate
        values = campaign.landing_pages.active.filter_map { |lp| positive_integer(lp.metadata.to_h["expected_profit_yen"]) }
        if values.empty?
          values = business.action_candidates.active_for_ranking.where(action_type: %w[build_lp lp_experiment ui_improvement]).filter_map do |candidate|
            positive_integer(candidate.final_expected_value_yen)
          end
        end
        expected_profit = median(values) || 0
        expected_cv_values = campaign.landing_pages.active.filter_map { |lp| positive_decimal(lp.metadata.to_h["expected_cv"]) }
        expected_cv = median(expected_cv_values) || campaign.target_conversions.to_d
        hours = ESTIMATED_WORK_HOURS.fetch(purpose)
        {
          "expected_profit_yen" => expected_profit.to_i,
          "expected_cv" => expected_cv.to_f.round(2),
          "expected_hourly_value_yen" => hours.positive? ? (expected_profit / hours).round : 0,
          "estimated_work_hours" => hours,
          "source" => values.any? ? "existing_lp_expected_profit" : "insufficient_profit_evidence"
        }
      end

      def confidence
        score = 0.3
        score += 0.1 if evidence.dig("measurement", "ga4_connected")
        score += 0.1 if evidence.dig("measurement", "gsc_connected")
        score += 0.1 if evidence["existing_landing_pages"].any?
        score += 0.1 if evidence["search_queries"].any?
        score.round(2).clamp(0.3, 0.8)
      end

      def fixed_keywords
        advanced["keywords"].to_s.split(/[、,\n]/).map(&:strip).compact_blank
      end

      def observed_keywords
        words = evidence["search_queries"].first(8)
        words.presence || [ business.name, "#{business.name} #{PURPOSES.fetch(purpose)}" ]
      end

      def search_intent(label)
        {
          "seo" => "課題の解決方法を検索し、具体的なサービスを比較検討している",
          "google_ads" => "広告から短時間で内容を理解し、相談または申込へ進みたい",
          "meta_ads" => "初めて知ったサービスの価値を理解し、興味を行動へ変えたい",
          "comparison" => "複数案の違いを把握し、自分に合う選択肢を決めたい",
          "regional" => "対象地域で利用できる具体的なサービスを探している"
        }.fetch(purpose, "サービスの価値を理解し、次の行動を判断したい")
      end

      def purpose_outcome(label)
        label.in?(%w[Google広告 Meta広告 SNS メール]) ? "次の行動まで迷わない" : "必要な答えが見つかる"
      end

      def strategy_reason(keywords)
        "#{campaign.name}の#{PURPOSES.fetch(purpose)}目的として、取得済み情報#{keywords.any? ? 'と検索語' : ''}から制作要件を生成。"
      end

      def response_schema
        {
          type: "object", additionalProperties: false, required: response_properties.keys,
          properties: response_properties
        }
      end

      def response_properties
        @response_properties ||= {
          "keywords" => { type: "array", items: { type: "string" }, maxItems: 20 },
          "search_intent" => { type: "string" }, "target" => { type: "string" }, "persona" => { type: "string" },
          "usp" => { type: "string" }, "headline" => { type: "string" }, "subheadline" => { type: "string" },
          "cta" => { type: "string" }, "faq" => { type: "array", items: { type: "string" }, maxItems: 12 },
          "comparison_table" => { type: "array", items: { type: "string" }, maxItems: 12 },
          "structure" => { type: "array", items: { type: "string" }, maxItems: 16 },
          "seo_title" => { type: "string" }, "meta_description" => { type: "string" },
          "image_instructions" => { type: "array", items: { type: "string" }, maxItems: 10 },
          "color_direction" => { type: "string" }, "design_direction" => { type: "string" }, "reason" => { type: "string" }
        }
      end

      def median(values)
        sorted = values.compact.sort
        return if sorted.empty?
        middle = sorted.length / 2
        sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.to_d
      end

      def positive_integer(value)
        number = value.to_i
        number if number.positive?
      end

      def positive_decimal(value)
        number = value.to_d
        number if number.positive?
      end
    end
  end
end
