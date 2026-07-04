module Aicoo
  module Owner
    class AutoRevisionLoopBoard
      Row = Data.define(
        :key,
        :record,
        :action_candidate,
        :auto_revision_task,
        :business,
        :title,
        :expected_profit_yen,
        :expected_hourly_value_yen,
        :priority_score,
        :current_state,
        :next_action_label,
        :next_action_path,
        :next_action_method,
        :next_action_reason,
        :updated_at,
        :detail
      )
      Summary = Data.define(
        :waiting_to_copy_count,
        :codex_running_count,
        :pr_waiting_count,
        :confirmation_waiting_count,
        :result_waiting_count,
        :failed_count,
        :completed_count
      )
      Result = Data.define(:summary, :rows, :selected, :next_action)

      def initialize(selected_key: nil, limit: 30)
        @selected_key = selected_key
        @limit = limit
      end

      def call
        rows = (task_rows + candidate_rows)
          .uniq(&:key)
          .sort_by { |row| [ -row.priority_score.to_d, row.updated_at || Time.zone.at(0) ] }
          .first(limit)
        selected = rows.find { |row| row.key == selected_key } || rows.first

        Result.new(
          summary: summary_for(rows),
          rows:,
          selected:,
          next_action: selected
        )
      end

      private

      attr_reader :selected_key, :limit

      def task_rows
        AutoRevisionTask
          .includes(:business, :action_candidate, :codex_submission, :auto_revision_executions)
          .where.not(status: %w[canceled])
          .by_priority
          .limit(limit)
          .map { |task| row_for_task(task) }
      end

      def candidate_rows
        ActionCandidate
          .includes(:business, :auto_revision_tasks, :action_result)
          .active_for_ranking
          .where.not(department: "new_business")
          .where.missing(:auto_revision_tasks)
          .by_recommendation
          .limit(limit)
          .map { |candidate| row_for_candidate(candidate) }
      end

      def row_for_task(task)
        candidate = task.action_candidate
        Row.new(
          key: "auto_revision_task:#{task.id}",
          record: task,
          action_candidate: candidate,
          auto_revision_task: task,
          business: task.business,
          title: task.title,
          expected_profit_yen: candidate&.expected_profit_yen.to_i,
          expected_hourly_value_yen: candidate&.expected_hourly_value_yen.to_i,
          priority_score: task.priority_score.to_d,
          current_state: state_for_task(task),
          next_action_label: next_action_for_task(task)[:label],
          next_action_path: next_action_for_task(task)[:path],
          next_action_method: next_action_for_task(task)[:method],
          next_action_reason: next_action_for_task(task)[:reason],
          updated_at: task.updated_at,
          detail: detail_for_task(task)
        )
      end

      def row_for_candidate(candidate)
        Row.new(
          key: "action_candidate:#{candidate.id}",
          record: candidate,
          action_candidate: candidate,
          auto_revision_task: nil,
          business: candidate.business,
          title: candidate.title,
          expected_profit_yen: candidate.expected_profit_yen.to_i,
          expected_hourly_value_yen: candidate.expected_hourly_value_yen.to_i,
          priority_score: candidate.final_score.to_d,
          current_state: "改修タスク化待ち",
          next_action_label: "自動改修タスク化",
          next_action_path: Rails.application.routes.url_helpers.auto_revision_tasks_path(action_candidate_id: candidate.id),
          next_action_method: :post,
          next_action_reason: "改善案はありますが、AutoRevisionTaskがまだありません。",
          updated_at: candidate.updated_at,
          detail: detail_for_candidate(candidate)
        )
      end

      def state_for_task(task)
        case task.status
        when "draft", "waiting_approval" then "承認待ち"
        when "approved", "ready_for_codex", "queued" then "Codex送信待ち"
        when "sent_to_codex" then "Codex作業待ち"
        when "running" then "Codex作業中"
        when "completed", "succeeded", "partial_succeeded" then task.action_candidate&.action_result ? "完了" : "結果登録待ち"
        when "failed" then "失敗"
        else task.status
        end
      end

      def next_action_for_task(task)
        routes = Rails.application.routes.url_helpers
        case task.status
        when "draft", "waiting_approval"
          action("承認する", routes.approve_auto_revision_task_path(task), :patch, "承認するとCodex用プロンプト確認へ進めます。")
        when "approved", "ready_for_codex", "queued"
          action("Codex用プロンプトをコピー", routes.export_codex_prompt_auto_revision_task_path(task), :get, "Cloud Codex API連携前のため、手動コピーで送信します。")
        when "sent_to_codex"
          action("実装開始にする", routes.start_implementation_auto_revision_task_path(task), :patch, "Codexへ渡した後の作業状態へ進めます。")
        when "running"
          action("実装済みにする", nil, nil, "右側の実装結果フォームから結果を登録してください。")
        when "completed", "succeeded", "partial_succeeded"
          if task.action_candidate&.action_result
            action("再評価する", routes.evaluate_action_result_path(task.action_candidate.action_result), :post, "実績と予測の差分を再評価します。")
          else
            action("ActionResultを登録", nil, nil, "右側のActionResultフォームで学習データ化します。")
          end
        when "failed"
          action("再実行する", routes.retry_execution_auto_revision_task_path(task), :patch, "失敗理由を確認し、再実行キューへ戻します。")
        else
          action("詳細を見る", routes.auto_revision_task_path(task), :get, "詳細画面で状態を確認します。")
        end
      end

      def action(label, path, method, reason)
        { label:, path:, method:, reason: }
      end

      def detail_for_task(task)
        {
          prompt: task.codex_prompt_markdown,
          target_url: task.action_candidate&.metadata.to_h["target_url"],
          changed_files: task.changed_files.presence || task.action_candidate&.metadata.to_h["target_files"],
          completion_criteria: task.action_candidate ? Aicoo::ActionCandidateExecutionBrief.new(task.action_candidate).completion_criteria : [],
          expected_effects: task.action_candidate ? Aicoo::ActionCandidateExecutionBrief.new(task.action_candidate).expected_effects : {},
          pr_url: latest_pr_url(task),
          deploy_status: latest_deploy_status(task),
          result_summary: task.result_summary,
          error_message: task.error_message
        }
      end

      def detail_for_candidate(candidate)
        brief = Aicoo::ActionCandidateExecutionBrief.new(candidate)
        {
          prompt: brief.prompt_markdown,
          target_url: brief.target[:url],
          changed_files: brief.file_changes,
          completion_criteria: brief.completion_criteria,
          expected_effects: brief.expected_effects,
          pr_url: nil,
          deploy_status: nil,
          result_summary: nil,
          error_message: nil
        }
      end

      def summary_for(rows)
        Summary.new(
          waiting_to_copy_count: rows.count { |row| row.current_state == "Codex送信待ち" },
          codex_running_count: rows.count { |row| row.current_state == "Codex作業中" },
          pr_waiting_count: rows.count { |row| row.detail[:pr_url].blank? && row.current_state.in?(%w[Codex作業中 Codex作業待ち]) },
          confirmation_waiting_count: rows.count { |row| row.current_state == "Codex作業待ち" },
          result_waiting_count: rows.count { |row| row.current_state == "結果登録待ち" },
          failed_count: rows.count { |row| row.current_state == "失敗" },
          completed_count: rows.count { |row| row.current_state == "完了" }
        )
      end

      def latest_pr_url(task)
        task.auto_revision_executions.recent.find { |execution| execution.pull_request_url.present? }&.pull_request_url ||
          task.codex_submission&.pull_request_url
      end

      def latest_deploy_status(task)
        task.auto_revision_executions.recent.find { |execution| execution.deploy_status.present? }&.deploy_status ||
          task.codex_submission&.deploy_status
      end
    end
  end
end
