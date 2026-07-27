module Aicoo
  class TodayOutcomeGrouping
    OUTCOME_KEY = "shop_information_verification".freeze
    VERIFICATION_ACTION_TYPES = %w[smoking_info_verify shop_phone_verify].freeze
    VERIFICATION_PATTERN = /
      喫煙(?:情報)?(?:を)?(?:確認|取得)|
      電話(?:で|番号へ)?(?:を)?(?:確認|架電)|
      架電|
      営業時間(?:を)?(?:確認|取得)|
      店舗(?:情報|ページ)(?:を)?(?:確認|取得)|
      SNS(?:で)?(?:を)?確認|
      Google(?:で)?(?:を)?確認|
      smoking(?:_info)?_verify|
      shop_phone_verify|
      shop_information_verification
    /ix
    DISTINCT_WORK_PATTERN = /
      電話番号(?:修正|変更|更新)|
      画像(?:追加|変更|更新)|
      口コミ(?:分析|対応)|
      SEO(?:改善|改修)|
      内部リンク|
      LP(?:改善|改修)|
      コード(?:改善|改修|修正)|
      記事(?:作成|改訂|更新|改善)|
      phone_number_(?:update|correction)|
      image_(?:add|update)|
      review_analysis
    /ix

    Group = Data.define(:key, :title, :candidates, :methods, :sources)

    class << self
      def key_for(candidate)
        return unless candidate.is_a?(ActionCandidate)
        return unless candidate.business_id.present?
        return unless candidate.execution_mode.to_s.in?(%w[manual_operation data_operation])

        metadata = Aicoo::RequestQueryContext.normalized_metadata(candidate)
        return if article_target(metadata).present?

        text = candidate_text(candidate, metadata)
        return if text.match?(DISTINCT_WORK_PATTERN)
        return unless VERIFICATION_ACTION_TYPES.include?(candidate.action_type.to_s) || text.match?(VERIFICATION_PATTERN)

        shop_id = shop_target_id(metadata)
        target_url = normalized_target_url(metadata)
        return if shop_id.blank? && target_url.blank?

        [
          OUTCOME_KEY,
          candidate.business_id,
          shop_id.presence || "-",
          target_url.presence || "-"
        ].join("::")
      end

      def group_for(candidate, scope: nil)
        key = key_for(candidate)
        return if key.blank?

        candidates = scope || ActionCandidate.active_for_ranking.where(business_id: candidate.business_id)
        members = candidates.to_a.select { |other| key_for(other) == key }
        return if members.size < 2

        Group.new(
          key:,
          title: title_for(members),
          candidates: members.sort_by { |member| [ -member_expected_value(member), member.id ] },
          methods: members.map { |member| method_label(member) }.uniq,
          sources: members.map { |member| source_label(member) }.uniq
        )
      end

      def title_for(candidates)
        members = Array(candidates)
        shop_name = members.filter_map { |candidate| shop_name_for(candidate) }.first || "対象店舗"
        text = members.map { |candidate| candidate_text(candidate, Aicoo::RequestQueryContext.normalized_metadata(candidate)) }.join(" ")
        smoking = text.match?(/喫煙|smoking/i)
        business_hours = text.match?(/営業時間|business.?hours/i)

        subject = if smoking && !business_hours
          "喫煙情報"
        elsif business_hours && !smoking
          "営業時間"
        else
          "店舗情報"
        end
        "#{shop_name}の#{subject}を確認する"
      end

      def method_label(candidate)
        text = candidate_text(candidate, Aicoo::RequestQueryContext.normalized_metadata(candidate))
        return "電話で確認" if candidate.action_type.to_s == "shop_phone_verify" || text.match?(/電話|架電|call/i)
        return "Googleで確認" if text.match?(/Google/i)
        return "SNSで確認" if text.match?(/SNS|Instagram|X(?:\s|$)|Facebook/i)
        return "店舗ページで確認" if text.match?(/店舗ページ|店舗情報(?:を)?開|公式サイト|Webサイト|website/i)

        "店舗情報を確認"
      end

      def method_specificity(candidate)
        {
          "電話で確認" => 4,
          "Googleで確認" => 3,
          "SNSで確認" => 2,
          "店舗ページで確認" => 1,
          "店舗情報を確認" => 0
        }.fetch(method_label(candidate), 0)
      end

      private

      def candidate_text(candidate, metadata)
        [
          candidate.action_type,
          candidate.title,
          metadata["action_group"],
          metadata["purpose"],
          metadata["goal"],
          metadata["outcome"],
          metadata["outcome_key"],
          metadata["action_outcome"],
          metadata["expected_outcome"],
          metadata["resolved_issue"],
          metadata["issue_key"],
          metadata["target_field"],
          metadata["missing_field"],
          metadata.dig("action_plan", "summary"),
          metadata.dig("action_plan", "goal"),
          metadata.dig("action_plan", "owner_next_step"),
          Array(metadata.dig("action_plan", "execution_steps")),
          metadata.dig("evidence", "issue_type"),
          metadata.dig("evidence", "reason")
        ].flatten.compact_blank.join(" ").encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      def shop_target_id(metadata)
        metadata["shop_id"].presence ||
          metadata["target_shop_id"].presence ||
          metadata["source_shop_id"].presence ||
          metadata.dig("shop", "id").presence ||
          metadata.dig("target_shop", "id").presence ||
          metadata["target_record_id"].presence
      end

      def article_target(metadata)
        metadata["article_id"].presence ||
          metadata["target_article_id"].presence ||
          metadata.dig("article", "id").presence
      end

      def normalized_target_url(metadata)
        raw = [
          metadata["target_url"],
          metadata["target_url_or_identifier"],
          metadata["page_path"],
          metadata.dig("action_plan", "target_url"),
          metadata.dig("action_plan", "target_url_or_identifier")
        ].compact_blank.first
        return if raw.blank?

        value = raw.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).unicode_normalize(:nfkc).downcase
        value = value.split(/[?#]/, 2).first
        value = value.sub(%r{/\z}, "") unless value == "/"
        value.presence
      end

      def shop_name_for(candidate)
        metadata = Aicoo::RequestQueryContext.normalized_metadata(candidate)
        value = metadata["shop_name"].presence ||
          metadata["target_shop_name"].presence ||
          metadata.dig("shop", "name").presence ||
          metadata.dig("target_shop", "name").presence ||
          metadata["target_name"].presence
        value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).presence
      end

      def source_label(candidate)
        candidate.generation_source.to_s.presence || "unknown"
      end

      def member_expected_value(candidate)
        candidate.final_expected_value_yen.presence ||
          candidate.expected_profit_yen.presence ||
          candidate.expected_total_value_yen.presence ||
          0
      end
    end
  end
end
