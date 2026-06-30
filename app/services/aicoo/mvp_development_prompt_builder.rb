module Aicoo
  class MvpDevelopmentPromptBuilder
    def initialize(business:, landing_page:, lp_summary:)
      @business = business
      @landing_page = landing_page
      @lp_summary = lp_summary
    end

    def call
      <<~PROMPT
        目的:
        LP検証で反応が出たBusinessを、同じBusiness内でMVP開発フェーズへ進める。

        Business名:
        #{business.name}

        解決する課題:
        #{landing_page.public_body.presence || business.description.presence || "LPで反応した課題を、MVPで実際に解決できる状態へ落とし込む。"}

        ターゲット:
        #{landing_page.public_subheadline.presence || business.description.presence || "LPに反応したユーザー"}

        LPで反応が良かった訴求:
        - LP: #{landing_page.public_headline}
        - PV: #{lp_summary.pv}
        - CTAクリック: #{lp_summary.cta_clicks}
        - CV: #{lp_summary.cv}
        - CVR: #{(lp_summary.cvr * 100).round(1)}%
        - GSCクリック/表示回数: #{lp_summary.gsc_clicks} / #{lp_summary.gsc_impressions}
        - 判定: #{lp_summary.verdict}

        必要な最小機能:
        - LPの約束を実現する入力フォームまたは申込導線
        - ユーザーが課題を登録できる最小画面
        - 管理者が登録内容を確認できる画面
        - 反応計測できるActivity Logging
        - 公開後に改善結果をAICOOへ戻せるログ

        課金モデル:
        #{pricing_model}

        初期価格案:
        #{initial_price}

        開発対象リポジトリ:
        #{repository_description}

        MVPで作らないもの:
        - 大規模な自動化
        - 複雑な権限管理
        - 決済の完全自動化
        - 管理画面の過度な作り込み
        - 本番データを破壊する処理

        完了条件:
        - MVPの最小画面が動作する
        - LPからMVP導線へ遷移できる
        - 登録またはCTAが計測できる
        - AICOO Activity Loggingの追加方針が明記されている
        - 関連テストが追加または更新されている
        - 確認コマンドが通る
      PROMPT
    end

    private

    attr_reader :business, :landing_page, :lp_summary

    def pricing_model
      landing_page.assumed_price_yen.present? ? "月額または初回課金を想定。LP価格仮説を初期値にする。" : "まずは無料登録または問い合わせで需要を確認し、CV後に価格を検証する。"
    end

    def initial_price
      landing_page.assumed_price_yen.present? ? "¥#{landing_page.assumed_price_yen.to_i}" : "未設定。MVP着手前に初期価格案を1つ決める。"
    end

    def repository_description
      config = business.codex_execution_target_config
      [
        "execution_type: #{config[:execution_type]}",
        "github_repo: #{config[:github_repo].presence || "-"}",
        "local_project_path: #{config[:local_project_path].presence || "-"}",
        "target_slug: #{config[:target_slug].presence || landing_page.published_slug.presence || "-"}",
        "target_paths: #{Array(config[:target_paths]).presence&.join(", ") || "-"}",
        "test_command: #{config[:test_command].presence || "-"}",
        "deploy_command: #{config[:deploy_command].presence || "-"}"
      ].join("\n")
    end
  end
end
