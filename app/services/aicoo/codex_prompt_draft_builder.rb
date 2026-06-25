module Aicoo
  class CodexPromptDraftBuilder
    def initialize(action_candidate)
      @action_candidate = action_candidate
      @business = action_candidate.business
    end

    def call
      CodexPromptDraft.create!(
        action_candidate:,
        business:,
        project_key: project_key,
        local_project_path: local_project_path,
        title: draft_title,
        objective: objective,
        prompt_body: prompt_body,
        risk_level: risk_level,
        status: "draft",
        generated_from: "action_candidate",
        safety_notes: safety_notes,
        verification_commands: verification_commands,
        metadata: metadata
      )
    end

    private

    attr_reader :action_candidate, :business

    def project_key
      business&.codex_project_key
    end

    def local_project_path
      business&.codex_local_project_path
    end

    def repository_name
      business&.codex_repository_name
    end

    def verification_commands
      business&.codex_verification_commands || CodexPromptDraft::DEFAULT_VERIFICATION_COMMANDS
    end

    def draft_title
      "Codex改定: #{action_candidate.title}"
    end

    def objective
      action_candidate.execution_prompt.presence ||
        action_candidate.description.presence ||
        action_candidate.evaluation_reason.presence ||
        action_candidate.title
    end

    def risk_level
      text = [
        action_candidate.title,
        action_candidate.description,
        action_candidate.action_type,
        action_candidate.execution_prompt,
        action_candidate.evaluation_reason
      ].join(" ").downcase

      return "high" if text.match?(/migration|db:migrate|認証|権限|課金|決済|billing|payment|削除|delete|destroy|credential|secret|token|daily run|scheduler|評価関数/)
      return "low" if text.match?(/copy|文言|タイトル|meta description|css|表示|記事|content|内部リンク|ui微修正/)

      "medium"
    end

    def safety_notes
      <<~TEXT.strip
        - db:drop / db:reset / drop database は絶対に実行しない
        - 既存機能を壊さない
        - 本番secretやtokenを表示しない
        - 高リスク変更は勝手に広げない
      TEXT
    end

    def prompt_body
      <<~PROMPT
        AICOO Codex Prompt Draft

        目的:
        #{objective}

        対象プロジェクト:
        - project_key: #{project_key.presence || "未設定"}
        - local_project_path: #{local_project_path.presence || "未設定"}
        - repository_name: #{repository_name.presence || "未設定"}

        対象Business:
        #{business&.name || "未設定"}

        元ActionCandidate:
        - ID: #{action_candidate.id}
        - title: #{action_candidate.title}
        - action_type: #{action_candidate.action_type}
        - generation_source: #{action_candidate.generation_source}
        - expected_value_yen: #{expected_value_yen}
        - success_probability: #{action_candidate.success_probability}

        期待値/理由:
        #{action_candidate.evaluation_reason.presence || action_candidate.description.presence || "AICOOが生成した改善候補です。"}

        実装してほしいこと:
        #{action_candidate.execution_prompt.presence || action_candidate.description.presence || action_candidate.title}

        変更範囲:
        - 対象ActionCandidateに必要な最小範囲に留める
        - 関連しないリファクタリングはしない
        - 対象プロジェクトが未設定の場合は、実装前に確認する

        壊してはいけない既存機能:
        - 既存のAICOO Dashboard / Owner Dashboard
        - ActionCandidate / ActionExecution / ActionResult / Learning Loop
        - Revenue計算式
        - Daily Run / Schedulerの既存挙動

        禁止事項:
        #{safety_notes}

        確認コマンド:
        #{verification_commands.map { |command| "- #{command}" }.join("\n")}

        完了報告:
        - 実装内容
        - 変更ファイル一覧
        - 実行した確認コマンド
        - 使い方
        - 残リスク
      PROMPT
    end

    def expected_value_yen
      action_candidate.final_expected_value_yen.presence ||
        action_candidate.expected_total_value_yen.presence ||
        action_candidate.immediate_value_yen.presence ||
        action_candidate.expected_profit_yen
    end

    def metadata
      {
        "action_type" => action_candidate.action_type,
        "generation_source" => action_candidate.generation_source,
        "final_score" => action_candidate.final_score&.to_s,
        "expected_value_yen" => expected_value_yen,
        "project_configured" => project_key.present? && local_project_path.present?
      }
    end
  end
end
