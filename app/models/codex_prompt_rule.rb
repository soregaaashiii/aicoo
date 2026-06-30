class CodexPromptRule < ApplicationRecord
  SCOPES = %w[global service].freeze
  RULE_CATEGORIES = %w[
    core
    rails
    ui
    test
    security
    activity_logging
    deploy
    service_specific
  ].freeze

  belongs_to :business, optional: true

  validates :name, :scope, :rule_category, :content, presence: true
  validates :scope, inclusion: { in: SCOPES }
  validates :rule_category, inclusion: { in: RULE_CATEGORIES }
  validates :business, presence: true, if: :service_scope?
  validates :business, absence: true, if: :global_scope?
  validates :name, uniqueness: { scope: %i[scope business_id] }
  validates :priority, numericality: { only_integer: true }

  scope :active, -> { where(active: true) }
  scope :global_rules, -> { where(scope: "global") }
  scope :service_rules, -> { where(scope: "service") }
  scope :ordered, -> { order(:priority, :rule_category, :name) }

  def self.ensure_defaults!
    DEFAULT_GLOBAL_RULES.each do |attributes|
      find_or_initialize_by(name: attributes[:name], scope: "global", business_id: nil).tap do |rule|
        rule.assign_attributes(attributes.merge(scope: "global", business: nil))
        rule.save!
      end
    end

    suelog = Business.real_businesses.find_by(name: "吸えログ")
    return unless suelog

    DEFAULT_SUELOG_RULES.each do |attributes|
      find_or_initialize_by(name: attributes[:name], scope: "service", business: suelog).tap do |rule|
        rule.assign_attributes(attributes.merge(scope: "service", business: suelog))
        rule.save!
      end
    end
  end

  def self.active_for_prompt(business = nil)
    rules = global_rules.active.ordered.to_a
    rules += service_rules.active.where(business:).ordered.to_a if business
    rules
  end

  def service_scope?
    scope == "service"
  end

  def global_scope?
    scope == "global"
  end

  DEFAULT_GLOBAL_RULES = [
    {
      name: "AICOO共通開発ルール",
      rule_category: "core",
      priority: 10,
      active: true,
      content: <<~TEXT.strip
        【AICOO共通開発ルール】
        * 既存機能を壊さない
        * 破壊的操作は禁止
        * db:drop / db:reset / database削除は禁止
        * 本番データを消す処理は禁止
        * 既存モデル・既存画面・既存Daily Runとの整合性を保つ
        * 変更後は関連テストを追加または更新する
        * UIは日本語を基本にする
        * 画面は迷わない導線にする
        * 一覧画面には必要最小限の情報だけ出す
        * 詳細情報は詳細画面に逃がす
        * Ownerが次に何をすればいいか分かる導線を必ず作る
      TEXT
    },
    {
      name: "AICOO Activity Logging共通ルール",
      rule_category: "activity_logging",
      priority: 20,
      active: true,
      content: <<~TEXT.strip
        【AICOO Activity Logging共通ルール】
        * 新しい重要な作業・更新・公開・収益導線変更が発生する処理を追加/変更する場合、AicooActivityLogger.log の追加を検討する
        * 以下のような変更はActivityとして記録対象にする
          * レコード作成
          * 重要フィールド更新
          * 公開状態変更
          * SEO title/meta変更
          * CTA変更
          * 価格変更
          * 課金導線追加
          * 収益導線追加
          * 外部流入施策
          * LP公開/更新
          * 記事公開/更新
        * Activityには以下を含める
          * activity_type
          * resource_type
          * resource_id
          * title
          * occurred_at
          * metadata
          * idempotency_key
        * idempotency_keyで重複送信を防ぐ
        * AICOO API送信に失敗した場合はローカルキューに保存し、後で再送できる設計にする
        * Loggerを追加できない場合でもDB差分検知で拾えるよう、created_at / updated_at と重要フィールドを正しく更新する
        * activity_type と metadata はサービス固有にしすぎず、AICOOが横断学習できる汎用表現にする
        * Activity Loggingは吸えログ専用にしない
        * 今後のRailsサービスにも流用できる汎用設計にする
      TEXT
    },
    {
      name: "AICOOテストルール",
      rule_category: "test",
      priority: 30,
      active: true,
      content: <<~TEXT.strip
        【テストルール】
        * モデル追加時はmodel testを追加する
        * controller追加時はrequest/controller testを追加する
        * service追加時はservice testを追加する
        * Daily Runにstepを追加した場合はstep成功/失敗/skipのテストを追加する
        * Activity Loggingは重複防止・送信失敗・再送のテストを入れる
      TEXT
    }
  ].freeze

  DEFAULT_SUELOG_RULES = [
    {
      name: "吸えログ Activity Loggingルール",
      rule_category: "activity_logging",
      priority: 10,
      active: true,
      content: <<~TEXT.strip
        【吸えログ Activity Loggingルール】
        吸えログでは以下の変更をAICOOの学習データとして必ず記録する。

        Shop系:
        * Shop作成
          * activity_type: shop_created
          * metadata: area, smoking_status, station, source, tabelog_url
        * smoking_status変更
          * activity_type: smoking_status_updated
          * metadata: before, after, area
        * 喫煙情報確認済み化
          * activity_type: smoking_verified
          * metadata: area, smoking_status
        * 電話番号/住所/営業時間/定休日の更新
          * activity_type: shop_profile_updated
          * metadata: changed_fields, area
        * status変更
          * activity_type: shop_status_changed
          * metadata: before, after, area
        * アフィリエイト/予約/地図/電話導線追加
          * activity_type: shop_conversion_path_added
          * metadata: conversion_type, area

        Article系:
        * 記事作成
          * activity_type: article_created
        * 記事公開
          * activity_type: article_published
          * metadata: slug, area, target_keyword
        * 記事更新
          * activity_type: article_updated
          * metadata: changed_fields, slug, area
        * SEO title/meta description変更
          * activity_type: article_seo_updated
          * metadata: before, after, slug
        * 内部リンク追加/変更
          * activity_type: internal_link_updated
          * metadata: source_article_id, target_article_id
        * 記事内店舗追加/削除
          * activity_type: article_shop_list_updated
          * metadata: added_shop_ids, removed_shop_ids, area

        評価ルール:
        * Shop作成や記事更新は、後日GA4/GSC/クリック/RevenueEventと紐付けて評価する
        * 評価期間は7日/14日/30日で見る
        * 店舗系は店舗詳細PV、エリア一覧PV、電話クリック、地図クリック、アフィリエイトクリックを見る
        * 記事系はGSC表示回数、クリック数、CTR、平均順位、記事PV、記事経由クリックを見る
        * 作業時間の推定値をmetadataまたはActivityLogに保存する
          * 新規店舗登録: 初期値20秒
          * 重複確認: 初期値15秒
          * 喫煙情報確認: 初期値30秒
          * 記事更新: 初期値は変更量から推定
      TEXT
    }
  ].freeze
end
