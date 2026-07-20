module Aicoo
  module Lovable
    class PromptBuilder
      DEFAULT_STRUCTURE = [
        "ファーストビュー（サービス名、端的な価値、主CTA）",
        "対象ユーザーが抱える課題",
        "提供価値と特徴",
        "利用の流れ",
        "料金または問い合わせ導線",
        "FAQ",
        "最終CTA"
      ].freeze

      def initialize(business:, landing_page:, previous_version: nil, learning_version: nil, best_version: nil, change_request: nil)
        @business = business
        @landing_page = landing_page
        @previous_version = previous_version
        @learning_version = learning_version
        @best_version = best_version
        @change_request = change_request
        @metadata = business.metadata.to_h.deep_stringify_keys
      end

      def call
        [ role_and_goal, business_context, content_requirements, design_requirements, implementation_requirements, revision_context ].compact_blank.join("\n\n")
      end

      private

      attr_reader :business, :landing_page, :previous_version, :learning_version, :best_version, :change_request, :metadata

      def role_and_goal
        <<~PROMPT.strip
          あなたはLovableのLPデザイナー兼フロントエンド実装者です。
          以下のBusinessのコンバージョン用Landing Pageを、実際にPreviewできる完成状態で作成してください。
          デザインとLP生成はLovableが担当し、公開用Repositoryへの反映・Git・PR・Deployは別工程でCodexが担当します。
          Lovable側から本番公開は行わないでください。
        PROMPT
      end

      def business_context
        <<~PROMPT.strip
          ## Business
          - サービス名: #{business.name}
          - 概要: #{business.description.presence || "未設定"}
          - カテゴリ: #{business.category.presence || business.business_type}
          - USP: #{value("usp", "unique_selling_proposition", fallback: business.description)}
          - ターゲット: #{value("target_audience", "target", "persona")}
          - CTA: #{value("cta", "primary_cta", fallback: landing_page.cta_text.presence || "問い合わせる")}
          - 価格: #{price_text}
          - 特徴: #{list_value("features", "feature_list")}
          - SEOキーワード: #{seo_keywords.join("、").presence || "未設定"}
          - 競合・比較対象: #{list_value("competitors", "competitor_names")}
          - ブランドカラー: #{list_value("brand_colors", "colors")}
          - トーン: #{value("tone", "brand_tone", "writing_tone")}
          - ロゴ: #{value("logo_url", "logo")}
          - 使用可能な画像: #{list_value("image_urls", "images")}
        PROMPT
      end

      def content_requirements
        <<~PROMPT.strip
          ## コピーと構成
          - 見出し案: #{landing_page.headline.presence || business.name}
          - 補足コピー: #{landing_page.subheadline.presence || business.description.presence || "未設定"}
          - 既存本文: #{landing_page.body.presence || "なし"}
          - FAQ: #{list_value("faq", "faqs")}
          - 必須構成:
          #{DEFAULT_STRUCTURE.map { |item| "  - #{item}" }.join("\n")}
          - 内部向けの説明やAICOO/Lovable/Codexという制作ツール名は公開コピーへ含めないこと。
          - 日本語として自然で、誇大表現を避け、CTAの行動を明確にすること。
        PROMPT
      end

      def design_requirements
        <<~PROMPT.strip
          ## デザイン
          - Businessの業種に合う実務的なデザインにする。
          - Desktop / Tablet / Mobileの全幅で崩れないレスポンシブ実装にする。
          - CTA、フォーム、hover/focus、loading、validation、empty/error状態を実装する。
          - 主役となるサービス・商品・場所をファーストビューで明確にする。
          - 読みやすいコントラストとキーボード操作を確保する。
          - 過剰なカード、装飾的なグラデーション、意味のない背景装飾は避ける。
        PROMPT
      end

      def implementation_requirements
        <<~PROMPT.strip
          ## 実装と計測
          - React + Vite + TypeScriptで、Codexが後からRepositoryへ移植しやすい構造にする。
          - CTAクリックを `generate_lead` として計測できるdata属性またはイベント関数を用意する。
          - title、description、OG、canonicalの設定箇所を明示する。
          - 画像にはaltを設定し、不要な外部依存を増やさない。
          - Preview URLで主要導線を確認できる状態まで完成させる。
        PROMPT
      end

      def revision_context
        return learning_context if change_request.blank? && previous_version.blank?

        <<~PROMPT.strip
          ## Version修正
          - 前Version: #{previous_version&.metadata.to_h&.dig("version_label") || "なし"}
          - 前Preview: #{previous_version&.metadata.to_h&.dig("preview_url") || "なし"}
          - 修正依頼: #{change_request.presence || "既存Versionを参照して新しい案を作成する"}
          - 修正対象以外の動作、計測、レスポンシブ対応を壊さないこと。
          #{best_version_context}

          #{learning_context}
        PROMPT
      end

      def learning_context
        learning = (learning_version || previous_version)&.metadata.to_h&.dig("learning").to_h
        return "" if learning.blank?

        <<~PROMPT.strip
          ## 過去VersionのLearning
          - CVR: #{learning["cvr"] || "未計測"}
          - CV: #{learning["conversions"] || "未計測"}
          - CTAクリック: #{learning["cta_clicks"] || "未計測"}
          - 滞在・離脱: #{learning.slice("engagement_seconds", "bounce_rate").to_json}
          - ROI: #{learning["roi"] || "未計測"}
          実測がある項目だけを次のデザイン判断へ反映してください。
        PROMPT
      end

      def best_version_context
        return "" unless best_version
        return "" if previous_version && best_version.id == previous_version.id

        learning = best_version.metadata.to_h["learning"].to_h
        <<~PROMPT.strip
          - 実績Best Version: #{best_version.metadata.to_h['version_label']}
          - Best Version CVR: #{learning['cvr'] || '未計測'}
          - Best Version ROI: #{learning['roi'] || '未計測'}
          - Best Versionの変更内容: #{best_version.metadata.to_h['change_request'].presence || '初回生成'}
          Best Versionの成果要因は参照してよいですが、今回指定された修正対象以外を無断で置き換えないでください。
        PROMPT
      end

      def value(*keys, fallback: nil)
        keys.each do |key|
          candidate = metadata[key]
          return candidate if candidate.present? && !candidate.is_a?(Array) && !candidate.is_a?(Hash)
        end
        fallback.presence || "未設定"
      end

      def list_value(*keys)
        keys.each do |key|
          candidate = metadata[key]
          return Array(candidate).map { |item| item.is_a?(Hash) ? item.to_json : item }.join("、") if candidate.present?
        end
        "未設定"
      end

      def price_text
        value("price", "price_yen", fallback: landing_page.assumed_price_yen&.then { |amount| "#{amount}円" })
      end

      def seo_keywords
        stored = Array(metadata["seo_keywords"]).compact_blank
        return stored.first(12) if stored.any?

        business.business_serp_keywords.order(priority_score: :desc).limit(12).pluck(:keyword)
      end
    end
  end
end
