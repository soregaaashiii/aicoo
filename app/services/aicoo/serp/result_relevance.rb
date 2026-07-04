module Aicoo
  module Serp
    class ResultRelevance
      DEFAULT_THRESHOLD = 25
      SUELOG_TERMS = %w[
        喫煙
        喫煙可
        喫煙可能
        飲食店
        居酒屋
        カフェ
        バー
        大阪
        梅田
        難波
        紙タバコ
        加熱式
        食べログ
        Googleマップ
        グーグルマップ
        Retty
        retty
      ].freeze
      SUELOG_NEGATIVE_TERMS = %w[
        ログ管理
        操作ログ
        システムログ
        監査ログ
        勤怠
        業務日報
        log
        logging
      ].freeze

      Result = Data.define(:result, :score, :matched_terms, :excluded, :reason)

      def initialize(business:, query:, threshold: DEFAULT_THRESHOLD)
        @business = business
        @query = query.to_s
        @threshold = threshold
      end

      def score(result)
        text = result_text(result)
        matched = domain_terms.select { |term| text.include?(term.downcase) }
        score = matched.size * 18

        if business_name.present? && text.include?(business_name.downcase)
          matched << business_name
          score += 35
        end

        negative = negative_terms.select { |term| text.include?(term.downcase) }
        score -= negative.size * 35

        reason =
          if score >= threshold
            "関連語: #{matched.uniq.join(', ')}"
          elsif negative.any?
            "Business領域外の語を検出: #{negative.uniq.join(', ')}"
          else
            "Business領域との一致が不足"
          end

        Result.new(
          result:,
          score: [ score, 0 ].max,
          matched_terms: matched.uniq,
          excluded: score < threshold,
          reason:
        )
      end

      def scored_results(results)
        Array(results).map { |result| score(result) }
      end

      def relevant_results(results)
        scored_results(results).reject(&:excluded).map(&:result)
      end

      def branded_query?
        business_name.present? && query.downcase.include?(business_name.downcase)
      end

      def domain_terms
        return SUELOG_TERMS if suelog?

        [
          business&.category,
          business&.business_type,
          business&.description.to_s.scan(/[[:word:]ぁ-んァ-ヶ一-龠ー]+/).first(8)
        ].flatten.compact_blank.map(&:to_s)
      end

      private

      attr_reader :business, :query, :threshold

      def business_name
        @business_name ||= business&.name.to_s
      end

      def suelog?
        business_name.include?("吸えログ")
      end

      def negative_terms
        suelog? ? SUELOG_NEGATIVE_TERMS : []
      end

      def result_text(result)
        [
          value_for(result, "title"),
          value_for(result, "url"),
          value_for(result, "snippet"),
          value_for(result, "displayed_url")
        ].compact.join(" ").downcase
      end

      def value_for(result, key)
        if result.respond_to?(:[])
          value = result[key]
          return value if value.present?

          symbol_key = key.to_sym
          return result[symbol_key] if result.respond_to?(:key?) && result.key?(symbol_key)
        end

        return result.public_send(key) if result.respond_to?(key)

        nil
      end
    end
  end
end
