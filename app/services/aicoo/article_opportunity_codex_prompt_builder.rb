module Aicoo
  class ArticleOpportunityCodexPromptBuilder
    def self.call(action_candidate:, gate:)
      new(action_candidate:, gate:).call
    end

    def initialize(action_candidate:, gate:)
      @candidate = action_candidate
      @gate = gate
      @metadata = action_candidate.metadata.to_h.deep_stringify_keys
      @brief = metadata["execution_brief"].to_h
    end

    def call
      <<~PROMPT
        指示された対象以外は変更しない。追加改修が必要だと判断しても、許可なく実装しない。

        ## ArticleOpportunity Codex Task

        対象Business: #{candidate.business&.name}
        ActionCandidate ID: #{candidate.id}
        value_model_name: #{metadata["value_model_name"]}
        analysis_source: #{metadata["analysis_source"]}
        opportunity_type: #{metadata["opportunity_type"]}
        snapshot_id: #{metadata["snapshot_id"]}
        risk_level: #{gate.risk_level}

        ## Repository

        repository: #{profile&.effective_codex_repository_url.presence || "-"}
        base_branch: #{profile&.effective_codex_base_branch.presence || "main"}
        working_branch_prefix: #{profile&.effective_codex_working_branch_prefix.presence || "aicoo/"}
        auto_merge_enabled: false
        auto_deploy_enabled: false
        今回はCodex送信までです。自動merge、自動deploy、Render操作は行わない。

        ## Target Article

        article_id: #{brief.dig("target", "article_id")}
        article_title: #{brief.dig("target", "article_title")}
        article_path: #{brief.dig("target", "article_path")}
        target_url: #{brief.dig("target", "target_url")}
        target_type: #{brief.dig("target", "target_type")}

        ## Current State

        #{formatted_hash(brief["current_state"])}

        ## Evidence

        #{formatted_hash(brief["evidence"])}

        ## Recommended Changes

        #{formatted_array(brief["recommended_changes"])}

        ## Completion Conditions

        #{formatted_array(brief["completion_conditions"])}

        ## Expected Result

        #{formatted_hash(brief["expected_result"])}

        ## Safety

        prohibited_actions:
        #{formatted_array(brief.dig("safety", "prohibited_actions"))}

        safety:
        #{formatted_hash(brief["safety"])}

        ## Strict Constraints

        - 外部検索禁止
        - 未確認情報追加禁止
        - 新規店舗捏造禁止
        - 店舗レビュー生成禁止
        - execution_briefにないURL追加禁止
        - 対象記事以外の大規模変更禁止
        - main直接push禁止
        - 指定branchで作業
        - DB Migration禁止
        - unrelated refactor禁止
        - テスト未実行を成功扱いにしない
        - 想定ファイルが存在しない場合は実装を止めて報告
        - 新規記事ファイルを勝手に作らない

        ## First Step

        最初に対象記事の実装場所を特定してください。
        対象と無関係なファイルは変更しないでください。

        ## Required Report

        - 実装内容
        - 変更ファイル
        - 実行した確認コマンド
        - 未実行の確認がある場合はその理由
        - 残リスク
      PROMPT
    end

    private

    attr_reader :candidate, :gate, :metadata, :brief

    def profile
      gate.profile
    end

    def formatted_hash(value)
      value.to_h.deep_stringify_keys.map { |key, item| "- #{key}: #{format_value(item)}" }.join("\n").presence || "-"
    end

    def formatted_array(value)
      Array(value).map { |item| "- #{format_value(item)}" }.join("\n").presence || "-"
    end

    def format_value(value)
      case value
      when Hash
        value.to_json
      when Array
        value.map { |item| item.is_a?(Hash) ? item.to_json : item }.join(" / ")
      else
        value.presence || "-"
      end
    end
  end
end
