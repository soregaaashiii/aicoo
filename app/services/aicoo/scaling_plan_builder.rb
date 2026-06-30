module Aicoo
  class ScalingPlanBuilder
    def initialize(business:, scaling_summary:)
      @business = business
      @scaling_summary = scaling_summary
    end

    def call
      <<~PLAN
        目的:
        productionで成立したBusinessを、過剰投資せずScalingフェーズへ進める。

        Business名:
        #{business.name}

        現在の勝ち筋:
        - 月間売上: ¥#{scaling_summary.monthly_revenue_yen}
        - 有料ユーザー数: #{scaling_summary.paid_users}
        - 継続率: #{(scaling_summary.retention_rate * 100).round(1)}%
        - CVR: #{(scaling_summary.cvr * 100).round(1)}%
        - 粗利: ¥#{scaling_summary.gross_profit_yen}

        伸ばすべきチャネル:
        #{scaling_summary.recommended_investment}

        追加すべき施策:
        #{scaling_summary.improvement_room.map { |room| "- #{room}" }.join("\n")}

        やらない施策:
        - 大きな固定費が先に増える施策
        - 計測できない広告投資
        - LTV/CACが崩れる割引施策
        - 本番データを壊す変更

        予算上限:
        #{budget_limit_yen}円

        期待利益:
        #{expected_profit_yen}円

        失敗条件:
        - 7日後にCVRまたは有料転換が改善しない
        - 30日後に粗利が増えない
        - CACがLTVの1/3を超える
        - 解約率が上昇する

        7日後に見る指標:
        - CVR
        - 有料転換
        - CAC
        - 主要チャネル別登録数

        30日後に見る指標:
        - 月間売上
        - 粗利
        - LTV/CAC
        - 継続率
        - 解約率
      PLAN
    end

    private

    attr_reader :business, :scaling_summary

    def budget_limit_yen
      [ scaling_summary.gross_profit_yen * 0.3, 10_000 ].max.round
    end

    def expected_profit_yen
      [ scaling_summary.gross_profit_yen * 2, 50_000 ].max.round
    end
  end
end
