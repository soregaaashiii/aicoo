module Aicoo
  module Serp
    class BusinessIdeaQualityJudge
      SERVICE_NAME_PATTERN = /代行|支援|ツール|SaaS|受付|制作|運用|管理|ナビ|相談|改善|採用|集客|検索|予約|診断|プラットフォーム|サービス|チェックリスト|テンプレート/
      CTA_PATTERN = /使ってみたい|無料相談|お問い合わせ|資料請求|今すぐ|登録する|事前登録|申し込む|始める/
      DESCRIPTION_PATTERN = /向けに|新規事業候補|解決する|提供します|できます|です。|ます。/

      REQUIRED_FIELDS = {
        "business_name" => "事業名",
        "target_customer" => "顧客",
        "problem" => "課題",
        "offering" => "提供サービス",
        "revenue_model" => "収益モデル",
        "validation_method" => "検証方法"
      }.freeze

      Result = Data.define(
        :auto_publishable,
        :status,
        :score,
        :reasons,
        :missing_fields,
        :checks
      ) do
        def to_h
          {
            "auto_publishable" => auto_publishable,
            "status" => status,
            "score" => score,
            "reasons" => reasons,
            "missing_fields" => missing_fields,
            "checks" => checks
          }
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(attributes:, source_query: nil)
        @attributes = attributes.to_h
        @source_query = source_query.to_s.squish
      end

      def call
        missing = REQUIRED_FIELDS.filter_map { |key, label| label if value_for(key).blank? }
        checks = {
          "service_name_understandable" => understandable_service_name?,
          "customer_concrete" => concrete_text?("target_customer"),
          "problem_concrete" => concrete_text?("problem"),
          "offering_concrete" => concrete_text?("offering"),
          "has_revenue_model" => concrete_text?("revenue_model"),
          "has_validation_method" => concrete_text?("validation_method"),
          "not_query_rephrase" => !query_rephrase?,
          "not_cta_text" => !cta_text?,
          "not_description_text" => !description_text?
        }
        failed = checks.select { |_key, passed| !passed }.keys
        score = ((checks.values.count(true).to_d / checks.size) * 100).round
        auto_publishable = missing.empty? && failed.empty?

        Result.new(
          auto_publishable:,
          status: auto_publishable ? "auto_publishable" : "needs_edit",
          score:,
          reasons: reasons_for(missing, failed),
          missing_fields: missing,
          checks:
        )
      end

      private

      attr_reader :attributes, :source_query

      def value_for(key)
        case key
        when "offering"
          attributes["offering"].presence || attributes["solution"].presence || attributes["provided_service"].presence
        when "revenue_model"
          attributes["revenue_model"].presence || attributes["monetization"].presence
        when "validation_method"
          attributes["validation_method"].presence || attributes["validation_plan"].presence || attributes["validation_step"].presence
        else
          attributes[key].presence
        end.to_s.squish
      end

      def name
        value_for("business_name")
      end

      def understandable_service_name?
        name.length.between?(4, 36) && name.match?(SERVICE_NAME_PATTERN)
      end

      def concrete_text?(key)
        value_for(key).length >= 8
      end

      def query_rephrase?
        return false if source_query.blank? || name.blank?

        normalized_name = normalize(name.gsub(/の検証事業|検証事業|比較|料金|おすすめ|困る|面倒|できない/, ""))
        normalized_query = normalize(source_query)
        normalized_name == normalized_query || name.include?(source_query) || source_query.include?(name)
      end

      def cta_text?
        name.match?(CTA_PATTERN)
      end

      def description_text?
        name.length > 36 || name.match?(DESCRIPTION_PATTERN)
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]　]+/, "").strip
      end

      def reasons_for(missing, failed)
        reasons = []
        reasons << "不足項目: #{missing.join('、')}" if missing.any?
        reasons << "事業名だけでは提供サービスが分かりにくい" if failed.include?("service_name_understandable")
        reasons << "顧客が具体的ではありません" if failed.include?("customer_concrete")
        reasons << "課題が具体的ではありません" if failed.include?("problem_concrete")
        reasons << "提供サービスが具体的ではありません" if failed.include?("offering_concrete")
        reasons << "収益モデルが不足しています" if failed.include?("has_revenue_model")
        reasons << "検証方法が不足しています" if failed.include?("has_validation_method")
        reasons << "検索クエリの言い換えになっています" if failed.include?("not_query_rephrase")
        reasons << "CTA文が事業名になっています" if failed.include?("not_cta_text")
        reasons << "説明文が事業名になっています" if failed.include?("not_description_text")
        reasons.presence || [ "品質判定OK" ]
      end
    end
  end
end
