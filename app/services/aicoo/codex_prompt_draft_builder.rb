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

    def execution_target_config
      business&.codex_execution_target_config || {
        execution_type: "aicoo_internal",
        github_repo: nil,
        local_project_path: nil,
        target_slug: nil,
        target_paths: [],
        test_command: nil,
        deploy_command: nil,
        default_branch: "main",
        auto_deploy_enabled: false
      }
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

        Codex実行先設定:
        - execution_type: #{execution_target_config[:execution_type]}
        - github_repo: #{execution_target_config[:github_repo].presence || "未設定"}
        - local_project_path: #{execution_target_config[:local_project_path].presence || "未設定"}
        - target_slug: #{execution_target_config[:target_slug].presence || "未設定"}
        - target_paths:
        #{target_paths_prompt_lines}
        - test_command: #{execution_target_config[:test_command].presence || "未設定"}
        - deploy_command: #{execution_target_config[:deploy_command].presence || "未設定"}
        - default_branch: #{execution_target_config[:default_branch].presence || "main"}
        - auto_deploy_enabled: #{execution_target_config[:auto_deploy_enabled] ? "true" : "false"}

        実行先の扱い:
        #{execution_target_description}

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

        Execution Guide:
        #{execution_guide_text}

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
        "action_expansion" => action_expansion,
        "project_configured" => project_key.present? && local_project_path.present?,
        "codex_execution_target" => execution_target_config.stringify_keys
      }
    end

    def target_paths_prompt_lines
      paths = Array(execution_target_config[:target_paths])
      return "        - 未設定" if paths.empty?

      paths.map { |path| "        - #{path}" }.join("\n")
    end

    def execution_target_description
      case execution_target_config[:execution_type]
      when "external_repo"
        "external_repo: 別サービスのリポジトリを対象にする。対象repo/path/branchを確認してから変更する。"
      else
        "aicoo_internal: AICOO本体のLP、Business、設定、管理画面を対象にする。公開LPと管理画面の境界を壊さない。"
      end
    end

    def execution_guide_text
      expansion = action_expansion
      return "Action Expansion未生成、またはEvidence不足のため具体手順はありません。" if expansion.blank? || expansion["warning"]

      <<~TEXT.strip
        対象: #{expansion["target"].presence || "未特定"}
        対象URL: #{expansion["target_url"].presence || "未特定"}
        対象KW: #{expansion["target_keyword"].presence || "未特定"}
        所要時間: #{expansion["expected_minutes"].presence || "未算出"}分

        実行手順:
        #{Array(expansion["execution_steps"]).each_with_index.map { |step, index| "#{index + 1}. #{step}" }.join("\n")}

        完了条件:
        #{Array(expansion["completion_criteria"]).map { |criterion| "- #{criterion}" }.join("\n")}
      TEXT
    end

    def action_expansion
      action_candidate.metadata.to_h["action_expansion"].to_h
    end
  end
end
