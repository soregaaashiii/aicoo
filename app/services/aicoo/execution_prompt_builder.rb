module Aicoo
  class ExecutionPromptBuilder
    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      return non_code_execution_memo unless action_candidate.code_revision_execution_mode?

      <<~PROMPT
        # AICOO Action Execution 指示書

        ## 行動タイトル
        #{action_candidate.title}

        ## 期待利益
        #{action_candidate.expected_profit_yen.to_i}円

        ## 成功確率
        #{(action_candidate.success_probability.to_d * 100).round(1)}%

        ## 目的
        #{action_candidate.evaluation_reason.presence || action_candidate.description.presence || "AICOOが提案した行動候補を安全に実行する。"}

        ## 元の実行内容
        #{action_candidate.execution_prompt.presence || action_candidate.description.presence || action_candidate.title}

        #{execution_units_markdown}

        #{execution_brief.prompt_markdown}

        ## Codex実装指示
        - AICOOは判断情報だけを渡します。本文や長文修正文はここでは生成しません。
        - 記事作成が必要な場合は、記事生成AIが作成した本文を既存Article作成フローで登録・公開する範囲に留めてください。
        - 改善対象ページURLが未特定の場合は、候補ページ1位から順に実在するRails route/view/controllerを確認して対象を確定してください。
        - 指標名 clicks / phone_clicks / map_clicks / affiliate_clicks をURLとして扱わないでください。
        - 実在しないURLを実装対象・完了報告・ActionResultに書かないでください。

        ## 注意事項
        - 既存機能を壊さない
        - db:drop / db:reset / drop database は絶対に実行しない
        - 本番secretやtokenを表示しない
        - 高リスク変更は勝手に広げない
      PROMPT
    end

    private

    attr_reader :action_candidate

    def non_code_execution_memo
      presenter = Aicoo::ActionCandidateEvidencePresenter.new(action_candidate)
      plan = presenter.action_plan
      steps = Array(plan["execution_steps"]).compact_blank
      units = presenter.execution_units

      <<~MEMO
        # AICOO Action 作業メモ

        ## 今日やること
        #{plan["summary"].presence || action_candidate.metadata.to_h["concrete_task"].presence || action_candidate.title}

        ## 実行方法
        #{presenter.execution_mode_label}

        ## 対象
        #{non_code_target_label(plan, presenter)}

        ## 理由
        #{plan["goal"].presence || action_candidate.evaluation_reason.presence || action_candidate.description.presence || "-"}

        #{non_code_units_markdown(units)}

        ## 実行手順
        #{(steps.presence || [ "作業を実行する", "結果を確認する", "ActionResultへ登録する" ]).map.with_index(1) { |step, index| "#{index}. #{step}" }.join("\n")}

        ## 完了条件
        - 作業が完了している
        - 実行結果をActionResultへ登録できるメモがある
      MEMO
    end

    def non_code_units_markdown(units)
      return nil if units.blank?

      <<~MARKDOWN.strip
        ## 今日やる単位
        #{units.map.with_index(1) { |unit, index| execution_unit_line(unit, index) }.join("\n")}
      MARKDOWN
    end

    def execution_brief
      @execution_brief ||= Aicoo::ActionCandidateExecutionBrief.new(action_candidate)
    end

    def execution_units_markdown
      units = Aicoo::ActionCandidateEvidencePresenter.new(action_candidate).execution_units
      return nil if units.blank?

      <<~MARKDOWN.strip
        ## 今日やる単位
        #{units.map.with_index(1) { |unit, index| execution_unit_line(unit, index) }.join("\n")}

        ## 手作業系タスクとして扱う場合
        - 実行手順: 上の単位を上から順に実行し、完了した単位ごとにActionResultへ記録してください。
        - 対象エリア: #{units.filter_map { |unit| unit["area"] }.uniq.join(" / ").presence || "未特定"}
        - 対象ジャンル: #{units.filter_map { |unit| unit["genre"] }.uniq.join(" / ").presence || "未特定"}
        - 目標件数: #{units.sum { |unit| unit["target_amount"].to_i }}件
      MARKDOWN
    end

    def non_code_target_label(plan, presenter)
      raw = plan["target"].presence || plan["target_url_or_identifier"].presence || presenter.target_label
      return raw unless raw.to_s.match?(/\Ahttps?:\/\//i) || raw.to_s.start_with?("/")

      Aicoo::BusinessOwnedUrlPolicy.call(business: action_candidate.business, url: raw).url.presence || raw
    end

    def execution_unit_line(unit, index)
      [
        "#{index}. #{unit['label']}",
        unit["area"].present? ? "対象エリア: #{unit['area']}" : nil,
        unit["genre"].present? ? "対象ジャンル: #{unit['genre']}" : nil,
        unit["page_path"].present? ? "対象ページ: #{unit['page_path']}" : nil,
        unit["query"].present? ? "検索クエリ: #{unit['query']}" : nil,
        unit["target_amount"].present? ? "目標: #{unit['target_amount']}件" : nil,
        unit["estimated_minutes"].present? ? "想定時間: #{unit['estimated_minutes']}分" : nil,
        unit["reason"].present? ? "理由: #{unit['reason']}" : nil
      ].compact.join(" / ")
    end
  end
end
