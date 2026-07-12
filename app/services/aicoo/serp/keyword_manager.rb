module Aicoo
  module Serp
    class KeywordManager
      Result = Data.define(:added, :existing, :excluded, :invalid)
      SuggestionReport = Data.define(:added, :pending_existing, :existing, :execution_targets, :excluded, :invalid) do
        def size
          added.size
        end

        def no_new_suggestions?
          added.empty?
        end

        def reason_summary
          reasons = []
          reasons << "追加待ち #{pending_existing.size}件" if pending_existing.any?
          reasons << "既存候補 #{existing.size}件" if existing.any?
          reasons << "実行対象登録済み #{execution_targets.size}件" if execution_targets.any?
          reasons << "除外済み #{excluded.size}件" if excluded.any?
          reasons << "無効 #{invalid.size}件" if invalid.any?
          reasons.presence&.join(" / ") || "生成できる候補がありません"
        end
      end

      def self.add_manual_keywords!(business:, raw_keywords:)
        new(business).add_manual_keywords!(raw_keywords)
      end

      def self.generate_suggestions!(business:)
        new(business).generate_suggestions!
      end

      def self.generate_suggestions_report!(business:)
        new(business).generate_suggestions_report!
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
        generate_suggestions_report!.added
      end

      def generate_suggestions_report!
        added = []
        pending_existing = []
        existing = []
        execution_targets = []
        excluded = []
        invalid = []

        suggestion_rows.each do |attrs|
          normalized = BusinessSerpKeyword.normalize(attrs.fetch(:keyword))
          if normalized.blank?
            invalid << attrs
            next
          end

          keyword = business.business_serp_keywords.find_by(normalized_keyword: normalized)
          if keyword&.status == "excluded"
            excluded << keyword
            next
          elsif keyword&.status == "pending"
            pending_existing << keyword
            next
          elsif keyword
            existing << keyword
            next
          end

          serp_query = business.serp_queries.find_by(normalized_query: SerpQuery.normalize(attrs.fetch(:keyword)))
          if serp_query
            execution_targets << serp_query
            next
          end

          keyword = business.business_serp_keywords.find_or_initialize_by(normalized_keyword: normalized)
          keyword.assign_attributes(
            attrs.merge(
              keyword: attrs.fetch(:keyword),
              status: keyword.status.presence || "pending",
              source: attrs.fetch(:source, "ai_suggested")
            )
          )
          keyword.save!
          added << keyword
        end

        SuggestionReport.new(added:, pending_existing:, existing:, execution_targets:, excluded:, invalid:)
      end

      private

      attr_reader :business

      def suggestion_rows
        []
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
