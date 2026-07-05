module Aicoo
  class ActionPlanner
    Plan = Data.define(
      :summary,
      :goal,
      :execution_steps,
      :estimated_completion,
      :owner_output,
      :execution_mode,
      :execution_units,
      :target,
      :target_type,
      :target_url_or_identifier
    ) do
      def valid?
        summary.present? && execution_steps.any? && owner_output.present? && execution_units.any?
      end

      def to_metadata
        {
          "summary" => summary,
          "goal" => goal,
          "execution_steps" => execution_steps,
          "estimated_completion" => estimated_completion,
          "owner_output" => owner_output,
          "execution_mode" => execution_mode,
          "execution_units" => execution_units,
          "target" => target,
          "target_type" => target_type,
          "target_url_or_identifier" => target_url_or_identifier
        }.compact
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(opportunity, analyzer:)
      @opportunity = opportunity
      @analyzer = analyzer
      @issue = opportunity.source_issue
      @attrs = issue.metadata.to_h.deep_stringify_keys
    end

    def call
      Plan.new(
        summary: summary,
        goal: goal,
        execution_steps: execution_steps,
        estimated_completion: estimated_completion,
        owner_output: owner_output,
        execution_mode: execution_mode,
        execution_units: execution_units,
        target: target_label,
        target_type: target_type,
        target_url_or_identifier: target_url_or_identifier
      )
    end

    private

    attr_reader :opportunity, :analyzer, :issue, :attrs

    def pattern
      opportunity.opportunity_type.to_s
    end

    def execution_mode
      opportunity.execution_mode.presence || attrs["execution_mode"].presence || "manual_operation"
    end

    def summary
      concrete_task.presence || issue.title
    end

    def concrete_task
      attrs["concrete_task"].presence || issue.title
    end

    def goal
      case pattern
      when "demand_without_asset"
        "#{target_label}に対応する受け皿を作り、需要を流入に変える"
      when "high_impression_low_ctr"
        "表示されている入口のクリック理由を明確にしてCTRを上げる"
      when "rank_11_20_gap"
        "あと一歩で上位化できるページ/クエリの不足要素を補強する"
      when "traffic_without_conversion"
        "流入上位ページから#{conversion_label}へ進む導線を増やす"
      when "asset_without_traffic"
        "作成済み資産に流入導線を追加し、初回トラフィックを作る"
      when "activity_gap"
        "止まっている改善サイクルを再開し、学習データを増やす"
      when "data_quality_gap"
        "成果判断に必要な計測データを揃える"
      else
        issue.why
      end
    end

    def owner_output
      [
        "今日やること:",
        summary,
        "",
        "理由:",
        issue.why,
        "",
        "期待効果:",
        issue.expected_effect
      ].join("\n")
    end

    def execution_steps
      case pattern
      when "demand_without_asset"
        demand_without_asset_steps
      when "high_impression_low_ctr"
        ctr_steps
      when "rank_11_20_gap"
        rank_gap_steps
      when "traffic_without_conversion"
        conversion_path_steps
      when "asset_without_traffic"
        asset_traffic_steps
      when "activity_gap"
        activity_gap_steps
      when "data_quality_gap"
        data_quality_steps
      else
        generic_steps
      end
    end

    def execution_units
      units = Array(analyzer.execution_units_for(issue)).map { |unit| unit.to_h.deep_stringify_keys }
      return units if units.any?

      [ {
        "label" => summary,
        "target_amount" => issue.quantity.presence || 1,
        "estimated_minutes" => estimated_minutes,
        "reason" => issue.why,
        "target_type" => target_type,
        "target_identifier" => target_url_or_identifier
      }.compact ]
    end

    def target_label
      opportunity.target.to_h["label"].presence ||
        attrs["target_identifier"].presence ||
        attrs["source_query"].presence ||
        issue.title
    end

    def target_type
      attrs["target_type"].presence || "task"
    end

    def target_url_or_identifier
      attrs["target_url_or_identifier"].presence || attrs["target_identifier"].presence || target_label
    end

    def estimated_minutes
      (opportunity.expected_hours.to_d * 60).round
    end

    def estimated_completion
      "#{estimated_minutes}分"
    end

    def conversion_label
      Array(attrs.dig("required_resources", "conversion_events")).compact_blank.first || "CV"
    end

    def demand_without_asset_steps
      case target_type
      when "article"
        [
          "タイトルを「#{target_label}」に合わせて決める",
          "検索意図に合う記事構成を作る",
          "関連ページから内部リンクを追加する",
          "公開する",
          "ActionResult登録用に公開URLと変更メモを残す"
        ]
      when "lp_section"
        [
          "既存LPの該当セクション位置を決める",
          "#{target_label}に対応する見出しと説明を追加する",
          "CTAまでの導線を確認する",
          "公開する",
          "ActionResult登録用に変更メモを残す"
        ]
      else
        [
          "#{target_label}に対応する受け皿の形式を決める",
          "ページまたは導線を作成する",
          "関連導線を追加する",
          "公開する",
          "ActionResult登録用に変更メモを残す"
        ]
      end
    end

    def ctr_steps
      [
        "対象ページと検索クエリを確認する",
        "タイトルをクリック理由が分かる表現に修正する",
        "meta descriptionを検索意図に合わせて修正する",
        "公開する",
        "ActionResult登録用に変更前後のタイトル/metaを残す"
      ]
    end

    def rank_gap_steps
      [
        "対象クエリで不足している要素を1つ選ぶ",
        "FAQ・比較・内部リンクのうち最も足りない要素を追加する",
        "該当ページの導線を確認する",
        "公開する",
        "7日後に順位とCTRを確認できるようActionResultへ登録する"
      ]
    end

    def conversion_path_steps
      [
        "流入上位ページを#{issue.quantity}件選ぶ",
        "#{conversion_label}へ進むCTA位置を決める",
        "CTA文言とリンク先を追加する",
        "イベント計測が取れるか確認する",
        "ActionResult登録用に対象ページ一覧を残す"
      ]
    end

    def asset_traffic_steps
      [
        "対象資産を確認する",
        "流入元にできる既存ページを3件選ぶ",
        "内部リンクまたは導線を追加する",
        "公開状態を確認する",
        "ActionResult登録用にリンク追加箇所を残す"
      ]
    end

    def activity_gap_steps
      [
        "対象領域を1つ選ぶ",
        "30分以内で終わる小さな改善を実行する",
        "変更内容をActivity Logに残す",
        "ActionResult登録用に作業メモを残す"
      ]
    end

    def data_quality_steps
      [
        "不足している計測項目を確認する",
        "設定画面または計測イベントの状態を確認する",
        "取得できない理由をメモする",
        "修正または再認証が必要なら次のActionCandidateへつなげる",
        "ActionResult登録用に確認結果を残す"
      ]
    end

    def generic_steps
      [
        "対象を確認する",
        "作業内容を実行する",
        "結果を確認する",
        "ActionResultへ登録する"
      ]
    end
  end
end
