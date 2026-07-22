require "uri"

module Aicoo
  module LpIntegration
    class PromptBuilder
      GA4_EVENTS = %w[
        page_view
        cta_click
        contact_start
        contact_submit
        demo_request
        document_request
        pricing_view
        login_click
        scroll_50
        scroll_90
      ].freeze

      ACTIVITY_EVENTS = %w[
        lp_cta_clicked
        lead_created
        demo_requested
        meeting_scheduled
        proposal_sent
        contract_won
        contract_lost
        subscription_started
        subscription_cancelled
      ].freeze

      def initialize(overview)
        @overview = overview
      end

      def call
        <<~PROMPT
          # 独立事業LP取り込みタスク

          ## 目的

          #{value(business.name)}のLPを、外部の独立事業リポジトリへ安全に取り込み、計測・問い合わせ・公開確認まで整備してください。

          ## 対象

          - LP作成元種類: #{overview.lp_source_type_label}
          - 移植元リポジトリ: #{value(overview.lp_source_repository_url)}
          - 移植元ブランチ: #{value(overview.lp_source_branch)}
          - 移植元URL: #{value(overview.lp_source_url)}
          - 実装先リポジトリ: #{value(overview.app_repository_url)}
          - 実装先ブランチ: #{value(overview.app_branch)}
          - 実装先フレームワーク: #{value(overview.app_framework)}
          - LP実装先: #{value(overview.marketing_root_path)}
          - 本番URL: #{value(overview.production_url)}
          - Renderサービス: #{value(overview.render_service_name)}
          - GA4 Measurement ID: #{value(overview.ga4_measurement_id)}
          - GA4 Property ID: #{value(overview.ga4_property_id)}
          - GSC Site URL: #{value(overview.gsc_site_url)}
          - AICOO Activity API: #{activity_api_endpoint}
          - AICOO Business ID: #{business.id}
          - AICOO連携: #{overview.integration_enabled? ? "有効" : "無効"}
          - 自動デプロイ: #{overview.auto_deploy_enabled? ? "許可設定あり" : "禁止"}
          - 手動承認: #{overview.manual_approval_required? ? "必須" : "Execution Profile設定に従う"}

          未設定値は推測で補完せず、実装前に停止理由として報告してください。

          ## 絶対条件

          1. 実装対象は `#{value(overview.app_repository_url)}` だけです。
          2. AICOOのリポジトリを変更しないでください。
          3. LPを独立事業アプリの公開領域へ実装してください。
          4. 既存管理画面のCSS・JavaScript・認証・ルートを壊さないでください。
          5. LP専用レイアウト・CSS・JavaScript・画像領域を分離してください。
          6. 将来LPだけ別プロジェクトへ移動しやすい構造にしてください。
          7. CTAを実在する問い合わせフォームへ接続してください。
          8. 下記GA4イベントを設定してください。
          9. PC・スマートフォンを実ブラウザで確認してください。
          10. テスト、コミット、push、Renderデプロイ、本番確認を行ってください。ただし手動承認・自動デプロイ設定を必ず守ってください。
          11. 未確認を確認済みと報告しないでください。
          12. 指示外の変更をしないでください。

          ## Railsの場合の推奨構成

          既存構造を最初に調査し、衝突がない場合だけ次を採用してください。

          - `app/controllers/marketing/`
          - `app/views/marketing/`
          - `app/views/layouts/marketing.html.erb`
          - `app/assets/stylesheets/marketing/`
          - `app/javascript/controllers/marketing/`
          - `app/assets/images/marketing/`
          - `app/services/lead_capture/`
          - `app/services/aicoo/`

          標準URLは `/`、`/contact`、`/contact/thanks`、`/login`、`/home` です。既存ルートと衝突する場合は既存挙動を維持し、安全な代替案を選んでください。

          ## Lead設計

          LP問い合わせは契約企業のCustomerやInquiryと混同せず、`Lead → 商談 → 契約 → Organizationまたは契約アカウント`として扱ってください。

          Leadには会社名、担当者名、メール、電話番号、業種、問い合わせ種別、月間問い合わせ数、現在の受付方法、課題、希望内容、対応状態、UTM、landing_page、referrer、ga_client_id、created_atを必要最小限で保持してください。独立事業DBを正本とし、AICOOへ個人情報を送らないでください。

          ## GA4

          GA4 IDはコードへ直書きせず、独立事業側の`GA4_MEASUREMENT_ID`で管理してください。

          設定イベント:
          #{markdown_list(GA4_EVENTS)}

          `cta_name`、`page_path`、`request_type`、UTMを可能な範囲で付与してください。`contact_submit`はDB保存成功後だけ発火させ、フォーム表示や入力開始を成果扱いにしないでください。

          ## GSC

          Site URLは`#{value(overview.gsc_site_url)}`です。所有権確認は初回手動とし、新しいGSC取得基盤は作らないでください。

          ## AICOO Activity API

          AICOOへ送信するイベント:
          #{markdown_list(ACTIVITY_EVENTS)}

          payloadはbusiness_idまたは外部事業識別子、event_type、occurred_at、amount_yen、source、匿名化metadataだけに限定してください。tokenは環境変数で管理し、ログへ出さないでください。

          独立事業DBへの保存と利用者への成功応答を先に完了し、その後`AnalyticsDelivery`等のキューから`Aicoo::ActivityReporter`を非同期実行してください。送信状態はpending/sent/failed、attempts、last_error、last_attempted_at、sent_atを追跡し、失敗時は再送してください。

          `AICOO_INTEGRATION_ENABLED=false`または未設定でも、LP・問い合わせ・契約処理は正常に動作させてください。AICOO停止や送信失敗を独立事業本体の失敗にしてはいけません。

          ## 分離要件

          - 独立事業のコード、DB、認証、環境変数、Renderサービス、本番URLを正本とする
          - AICOOから独立事業DBへ書き込まない
          - GA4・GSC・独自ドメインは独立事業側の資産として管理する
          - AICOO専用コードを`app/services/aicoo/`等へ隔離する
          - AICOOへLPソースや顧客個人情報をコピーしない

          ## 完了確認

          - 既存構造とルートの調査
          - LP実装と問い合わせ保存
          - GA4イベント確認
          - AICOO非同期送信の失敗耐性確認
          - PC・スマートフォンの実ブラウザ確認
          - テスト結果
          - commit SHA、PR URL、Render deploy ID、本番URL
          - 未確認事項と停止理由
        PROMPT
      end

      private

      attr_reader :overview

      def business
        overview.business
      end

      def activity_api_endpoint
        base_url = ENV["AICOO_PUBLIC_BASE_URL"].presence || ENV["AICOO_API_URL"].presence
        base_url ? URI.join(base_url, "/api/aicoo/activity_logs").to_s : "AICOO_API_URL + /api/aicoo/activity_logs"
      rescue URI::InvalidURIError
        "AICOO_API_URL + /api/aicoo/activity_logs"
      end

      def value(raw)
        raw.presence || "未設定"
      end

      def markdown_list(values)
        values.map { |item| "- `#{item}`" }.join("\n")
      end
    end
  end
end
