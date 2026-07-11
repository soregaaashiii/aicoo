module Aicoo
  class BusinessTypePlaybook
    Decision = Data.define(:allowed, :preferred, :forbidden, :reason, :metadata)

    GENERIC_ACTION_TYPES = %w[
      serp_research
      market_research
      ui_improvement
      sales
      outsourcing
      automation
      pivot
      withdraw
      data_preparation
      evaluation_tuning
      learning_improvement
      opportunity_validation
      other
    ].freeze
    GENERIC_PLAYBOOK = lambda do |preferred_actions, preferred_labels|
      {
        allowed_actions: GENERIC_ACTION_TYPES + %w[
          seo_article seo_improvement new_article_candidate smoking_info_verify shop_phone_verify article_create article_update
          build_lp build_mvp feature_development
        ],
        allowed_labels: %w[改善 収益改善 導線改善 計測改善 学習改善],
        preferred_actions:,
        preferred_labels:,
        forbidden_actions: [],
        forbidden_labels: [],
        forbidden_patterns: []
      }
    end

    TYPE_LABELS = {
      "seo_media" => "SEOメディア",
      "directory" => "ディレクトリ",
      "saas" => "SaaS",
      "landing_page" => "LP検証",
      "mvp" => "MVP",
      "internal_tool" => "内部ツール",
      "marketplace" => "マーケットプレイス",
      "content_media" => "コンテンツメディア",
      "ecommerce" => "EC",
      "community" => "コミュニティ",
      "other" => "その他"
    }.freeze

    PLAYBOOKS = {
      "seo_media" => {
        allowed_actions: %w[
          seo_article
          seo_improvement
          new_article_candidate
          smoking_info_verify
          shop_phone_verify
          article_create
          article_update
          serp_research
          market_research
          ui_improvement
          sales
          automation
          data_preparation
          evaluation_tuning
          learning_improvement
          opportunity_validation
          withdraw
          other
        ],
        allowed_labels: %w[
          記事追加
          店舗追加
          タイトル改善
          メタ改善
          内部リンク
          構造化データ
          回遊改善
          CTA改善
          口コミ導線
          カテゴリ改善
        ],
        preferred_actions: %w[smoking_info_verify shop_phone_verify article_create article_update new_article_candidate seo_article seo_improvement],
        preferred_labels: %w[SEO改善 コンテンツ追加],
        forbidden_actions: %w[build_lp build_mvp feature_development],
        forbidden_labels: %w[公開LP作成 SaaS機能追加 無関係な価格変更],
        forbidden_patterns: [
          /公開LP(を|の)?(作成|用意|生成)|LPを(作成|用意|生成)|ランディングページ(を)?(作成|用意|生成)/i,
          /SaaS|機能追加|プロダクト機能/i,
          /価格変更|料金変更|プラン変更/i
        ]
      },
      "directory" => {
        allowed_actions: %w[seo_article seo_improvement new_article_candidate smoking_info_verify shop_phone_verify article_create article_update serp_research market_research ui_improvement sales automation data_preparation learning_improvement opportunity_validation other],
        allowed_labels: %w[掲載データ追加 カテゴリ改善 内部リンク 回遊改善 CTA改善 検索導線改善],
        preferred_actions: %w[seo_improvement data_preparation ui_improvement],
        preferred_labels: %w[掲載データ改善 導線改善],
        forbidden_actions: %w[build_lp feature_development],
        forbidden_labels: %w[無関係なLP作成 大規模SaaS機能追加],
        forbidden_patterns: [ /無関係なLP|SaaS機能/i ]
      },
      "saas" => {
        allowed_actions: GENERIC_ACTION_TYPES + %w[build_mvp feature_development],
        allowed_labels: %w[オンボーディング改善 機能改善 価格改善 継続率改善 CTA改善],
        preferred_actions: %w[feature_development ui_improvement sales],
        preferred_labels: %w[利用開始改善 継続率改善],
        forbidden_actions: %w[seo_article build_lp],
        forbidden_labels: %w[無関係な記事量産 無関係なLP作成],
        forbidden_patterns: [ /無関係な記事|記事量産|公開LP作成/i ]
      },
      "landing_page" => {
        allowed_actions: GENERIC_ACTION_TYPES + %w[build_lp build_mvp seo_improvement],
        allowed_labels: %w[LP改善 CTA改善 訴求改善 計測改善 MVP判定],
        preferred_actions: %w[ui_improvement build_mvp seo_improvement],
        preferred_labels: %w[LP改善 CTA改善 MVP検証],
        forbidden_actions: [],
        forbidden_labels: %w[本番サービス前提の大規模改修],
        forbidden_patterns: [ /本番サービス.*大規模/i ]
      },
      "mvp" => {
        allowed_actions: GENERIC_ACTION_TYPES + %w[build_mvp feature_development seo_improvement],
        allowed_labels: %w[MVP改善 機能改善 計測改善 CTA改善 課金導線改善],
        preferred_actions: %w[feature_development ui_improvement sales],
        preferred_labels: %w[MVP改善 課金導線改善],
        forbidden_actions: [],
        forbidden_labels: %w[検証と無関係な大規模拡張],
        forbidden_patterns: [ /無関係な大規模/i ]
      },
      "internal_tool" => {
        allowed_actions: %w[automation data_preparation evaluation_tuning learning_improvement ui_improvement other],
        allowed_labels: %w[自動化 運用改善 データ整備 精度改善 管理画面改善],
        preferred_actions: %w[automation data_preparation learning_improvement],
        preferred_labels: %w[自動化 運用安定化],
        forbidden_actions: %w[build_lp seo_article sales],
        forbidden_labels: %w[公開LP作成 SEO記事追加 収益導線追加],
        forbidden_patterns: [ /公開LP|SEO記事|収益導線/i ]
      },
      "marketplace" => GENERIC_PLAYBOOK.call(%w[ui_improvement sales automation], %w[流通改善 出品者改善 購入導線改善]),
      "content_media" => GENERIC_PLAYBOOK.call(%w[seo_article seo_improvement ui_improvement], %w[記事追加 SEO改善 回遊改善]),
      "ecommerce" => GENERIC_PLAYBOOK.call(%w[sales ui_improvement seo_improvement], %w[商品導線改善 価格改善 購入率改善]),
      "community" => GENERIC_PLAYBOOK.call(%w[ui_improvement automation], %w[投稿促進 継続率改善 通知改善]),
      "other" => GENERIC_PLAYBOOK.call(GENERIC_ACTION_TYPES + %w[seo_article seo_improvement build_lp build_mvp feature_development], %w[汎用改善])
    }.freeze

    class << self
      def for_type(business_type)
        PLAYBOOKS.fetch(business_type.to_s, PLAYBOOKS.fetch("other"))
      end

      def label_for(business_type)
        TYPE_LABELS.fetch(business_type.to_s, business_type.to_s)
      end
    end

    def initialize(business)
      @business = business
    end

    def call(attributes)
      attrs = attributes.to_h
      action_type = attrs[:action_type].presence || attrs["action_type"].presence || "other"
      text = searchable_text(attrs)
      forbidden = forbidden_action?(action_type, text)
      preferred = !forbidden && preferred_action?(action_type, text)
      allowed = !forbidden && allowed_action?(action_type)
      reason = reason_for(action_type:, allowed:, preferred:, forbidden:)

      Decision.new(
        allowed:,
        preferred:,
        forbidden:,
        reason:,
        metadata: metadata_for(action_type:, allowed:, preferred:, forbidden:, reason:)
      )
    end

    def allowed_actions
      playbook.fetch(:allowed_actions)
    end

    def preferred_actions
      playbook.fetch(:preferred_actions)
    end

    def forbidden_actions
      playbook.fetch(:forbidden_actions)
    end

    def allowed_labels
      playbook.fetch(:allowed_labels)
    end

    def preferred_labels
      playbook.fetch(:preferred_labels)
    end

    def forbidden_labels
      playbook.fetch(:forbidden_labels)
    end

    def business_type
      business&.business_type.presence || "other"
    end

    def business_type_label
      self.class.label_for(business_type)
    end

    private

    attr_reader :business

    def playbook
      @playbook ||= self.class.for_type(business_type)
    end

    def allowed_action?(action_type)
      allowed_actions.include?(action_type.to_s)
    end

    def preferred_action?(action_type, text)
      preferred_actions.include?(action_type.to_s) ||
        preferred_labels.any? { |label| text.include?(label) }
    end

    def forbidden_action?(action_type, text)
      forbidden_actions.include?(action_type.to_s) ||
        playbook.fetch(:forbidden_patterns).any? { |pattern| text.match?(pattern) } ||
        forbidden_labels.any? { |label| text.include?(label) }
    end

    def searchable_text(attrs)
      [
        attrs[:title] || attrs["title"],
        attrs[:description] || attrs["description"],
        attrs[:evaluation_reason] || attrs["evaluation_reason"],
        attrs[:execution_prompt] || attrs["execution_prompt"]
      ].join("\n")
    end

    def reason_for(action_type:, allowed:, preferred:, forbidden:)
      if forbidden
        "Business Typeが#{business_type_label}のため、#{action_type}は対象外です。"
      elsif preferred
        "Business Typeが#{business_type_label}のため、#{action_type}を優先します。"
      elsif allowed
        "Business Typeが#{business_type_label}のAllowed Actionです。"
      else
        "Business Typeが#{business_type_label}のAllowed Actionに含まれないため対象外です。"
      end
    end

    def metadata_for(action_type:, allowed:, preferred:, forbidden:, reason:)
      {
        "business_type" => business_type,
        "business_type_label" => business_type_label,
        "action_type" => action_type,
        "allowed" => allowed,
        "preferred" => preferred,
        "forbidden" => forbidden,
        "reason" => reason,
        "allowed_actions" => allowed_actions,
        "preferred_actions" => preferred_actions,
        "forbidden_actions" => forbidden_actions
      }
    end
  end
end
