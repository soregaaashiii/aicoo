module Aicoo
  class ExecutionPromptBuilder
    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
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

        #{execution_brief.prompt_markdown}

        ## Codex実装指示
        - 上記のBefore/Afterと「Codexへ渡す修正文」をそのまま実装してください。
        - 改善対象ページURLが未特定の場合は、候補ページ1位から順に実在するRails route/view/controllerを確認して対象を確定してください。
        - 指標名 clicks / phone_clicks / map_clicks / affiliate_clicks をURLとして扱わないでください。
        - 実在しないURLを実装対象・完了報告・ActionResultに書かないでください。
        - 修正対象ファイルに挙げたviews/controllers/servicesを優先し、必要最小限の変更に留めてください。

        ## 注意事項
        - 既存機能を壊さない
        - db:drop / db:reset / drop database は絶対に実行しない
        - 本番secretやtokenを表示しない
        - 高リスク変更は勝手に広げない
      PROMPT
    end

    private

    attr_reader :action_candidate

    def execution_brief
      @execution_brief ||= Aicoo::ActionCandidateExecutionBrief.new(action_candidate)
    end
  end
end
