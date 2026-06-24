module Aicoo
  class ExecutionPromptBuilder
    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      <<~PROMPT
        # AICOO Action Execution

        ## 行動タイトル
        #{action_candidate.title}

        ## 期待利益
        #{action_candidate.expected_profit_yen.to_i}円

        ## 成功確率
        #{(action_candidate.success_probability.to_d * 100).round(1)}%

        ## 目的
        #{action_candidate.evaluation_reason.presence || action_candidate.description.presence || "AICOOが提案した行動候補を安全に実行する。"}

        ## 実行内容
        #{action_candidate.execution_prompt.presence || action_candidate.description.presence || action_candidate.title}

        ## 完了条件
        - 実行内容に記載された作業が完了している
        - 変更内容または実行内容をresult_summaryへ記録できる
        - 実行後にActionResultへ進める状態になっている

        ## 注意事項
        - 既存機能を壊さない
        - db:drop / db:reset / drop database は絶対に実行しない
        - 本番secretやtokenを表示しない
        - 高リスク変更は勝手に広げない
      PROMPT
    end

    private

    attr_reader :action_candidate
  end
end
