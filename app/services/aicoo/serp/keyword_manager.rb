module Aicoo
  module Serp
    class KeywordManager
      Result = Data.define(:added, :existing, :excluded, :invalid)

      def self.add_manual_keywords!(business:, raw_keywords:)
        new(business).add_manual_keywords!(raw_keywords)
      end

      def self.generate_suggestions!(business:)
        new(business).generate_suggestions!
      end

      def initialize(business)
        @business = business
      end

      def add_manual_keywords!(raw_keywords)
        added = []
        existing = []
        excluded = []
        invalid = []

        BusinessSerpKeyword.parse_keywords(raw_keywords).each do |keyword|
          normalized = BusinessSerpKeyword.normalize(keyword)
          if normalized.blank?
            invalid << keyword
            next
          end

          row = business.business_serp_keywords.find_by(normalized_keyword: normalized)
          if row&.status == "excluded"
            excluded << row
          elsif row
            existing << row
          else
            added << business.business_serp_keywords.create!(
              keyword:,
              source: "manual",
              status: "active",
              priority_score: 70,
              confidence: 80,
              reason: "手入力で追加"
            )
          end
        end

        Result.new(added:, existing:, excluded:, invalid:)
      end

      def generate_suggestions!
        suggestion_rows.filter_map do |attrs|
          normalized = BusinessSerpKeyword.normalize(attrs.fetch(:keyword))
          next if normalized.blank?
          next if business.business_serp_keywords.where(normalized_keyword: normalized, status: %w[active paused archived excluded]).exists?

          keyword = business.business_serp_keywords.find_or_initialize_by(normalized_keyword: normalized)
          keyword.assign_attributes(
            attrs.merge(
              keyword: attrs.fetch(:keyword),
              status: keyword.status.presence || "pending",
              source: attrs.fetch(:source, "ai_suggested")
            )
          )
          keyword.save!
          keyword
        end
      end

      private

      attr_reader :business

      def suggestion_rows
        [
          business_name_keyword,
          category_keyword,
          intent_keyword("比較", "比較検討"),
          intent_keyword("おすすめ", "店舗・サービス探索"),
          latest_serp_related_keyword
        ].compact.uniq { |attrs| BusinessSerpKeyword.normalize(attrs.fetch(:keyword)) }
      end

      def business_name_keyword
        return if business.name.blank?

        {
          keyword: business.name,
          source: "ai_suggested",
          priority_score: 55,
          opportunity_score: 50,
          confidence: 50,
          reason: "Business名から生成",
          search_intent: "指名検索・カテゴリ確認"
        }
      end

      def category_keyword
        tokens = [ business.name, business.category.presence || business.business_type ].compact_blank
        return if tokens.blank?

        {
          keyword: tokens.join(" "),
          source: "ai_suggested",
          priority_score: 60,
          opportunity_score: 55,
          confidence: 45,
          reason: "Businessカテゴリから生成",
          search_intent: "カテゴリ検索"
        }
      end

      def intent_keyword(suffix, intent)
        return if business.name.blank?

        {
          keyword: "#{business.name} #{suffix}",
          source: "ai_suggested",
          priority_score: 50,
          opportunity_score: 45,
          confidence: 40,
          reason: "検索意図テンプレートから生成",
          search_intent: intent
        }
      end

      def latest_serp_related_keyword
        related = business.serp_analyses.successful.order(analyzed_at: :desc, created_at: :desc)
                          .filter_map { |analysis| analysis.raw_summary.to_h.fetch("related_searches", []).first }
                          .first
        return if related.blank?

        {
          keyword: related.to_s,
          source: "serp_related",
          priority_score: 65,
          opportunity_score: 60,
          confidence: 55,
          reason: "SERP related searchesから生成",
          search_intent: "関連検索"
        }
      end
    end
  end
end
