module Aicoo
  class ProductionDevelopmentPromptBuilder
    def initialize(business:, business_service:, mvp_summary:)
      @business = business
      @business_service = business_service
      @mvp_summary = mvp_summary
    end

    def call
      <<~PROMPT
        目的:
        MVPで反応が出たBusinessを、本番運用できるproductionフェーズへ進める。

        Business名:
        #{business.name}

        MVPの結果:
        - サービスURL: #{mvp_summary.service_url}
        - 登録数: #{mvp_summary.registrations}
        - アクティブユーザー数: #{mvp_summary.active_users}
        - 無料利用数: #{mvp_summary.free_users}
        - 有料ユーザー数: #{mvp_summary.paid_users}
        - 売上: ¥#{mvp_summary.revenue_yen}
        - CVR: #{(mvp_summary.cvr * 100).round(1)}%
        - 継続率: #{(mvp_summary.retention_rate * 100).round(1)}%
        - 解約数: #{mvp_summary.churn_count}
        - 判定: #{mvp_summary.verdict}

        現在の課題:
        #{business.description.presence || "MVPを本番運用へ移すため、課金・監視・管理・計測を整える必要があります。"}

        本番運用に必要な改善:
        - 課金導線
        - ログイン/権限
        - 管理画面
        - 計測
        - エラー監視
        - Activity Logging
        - 本番運用手順

        課金導線:
        Stripeまたは既存の課金導線を使い、最低限の申込/支払い/問い合わせ導線を設計してください。

        ログイン/権限:
        MVPに必要な最小限のユーザー識別と管理者権限だけを実装してください。

        管理画面:
        登録、問い合わせ、課金状態、Activityを確認できる最小画面を作ってください。

        計測:
        GA4/GSC/RevenueEvent/BusinessActivityLogへ、公開・CTA・課金導線変更・登録を記録してください。

        エラー監視:
        重要処理の失敗をAICOO側で追えるよう、ログと失敗状態を残してください。

        最初に作らないもの:
        - 複雑な権限階層
        - 大規模な自動化
        - 高度な分析画面
        - 複雑なプラン体系
        - 本番データを削除する処理

        開発対象:
        #{repository_description}

        完了条件:
        - 本番運用に必要な課金/登録導線が動作する
        - 管理者が登録・課金・問い合わせを確認できる
        - Activity Logging方針が実装または明記されている
        - エラー時に原因が画面またはログで分かる
        - 関連テストが追加または更新されている
        - 確認コマンドが通る
      PROMPT
    end

    private

    attr_reader :business, :business_service, :mvp_summary

    def repository_description
      config = business.codex_execution_target_config
      [
        "execution_type: #{config[:execution_type]}",
        "github_repo: #{business_service.repository.presence || config[:github_repo].presence || "-"}",
        "local_project_path: #{config[:local_project_path].presence || "-"}",
        "target_slug: #{config[:target_slug].presence || business_service.domain.presence || "-"}",
        "target_paths: #{Array(config[:target_paths]).presence&.join(", ") || "-"}",
        "test_command: #{config[:test_command].presence || "-"}",
        "deploy_command: #{config[:deploy_command].presence || business_service.deploy_target.presence || "-"}"
      ].join("\n")
    end
  end
end
