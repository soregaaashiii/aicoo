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
        :progress_percent,
        :progress_label,
        :stuck_reason,
        :bucket,
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
        Aicoo::AutoRevisionAutopilot.sweep(limit:)
        rows = (task_rows + candidate_rows)
          .uniq(&:key)
          .sort_by { |row| [ -row.priority_score.to_d, (row.record.created_at || Time.zone.at(0)).to_i, -row.record.id.to_i ] }
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
          .to_a
          .sort_by { |task| expected_value_sort_key(task.action_candidate, task) }
          .first(limit)
          .map { |task| row_for_task(task) }
      end

      def candidate_rows
        ActionCandidate
          .includes(:business, :auto_revision_tasks, :action_result)
          .active_for_ranking
          .where.not(department: "new_business")
          .where.missing(:auto_revision_tasks)
          .to_a
          .sort_by { |candidate| expected_value_sort_key(candidate, candidate) }
          .first(limit)
          .map { |candidate| row_for_candidate(candidate) }
      end

      def row_for_task(task)
        candidate = task.action_candidate
        expected_value_yen = expected_value_yen_for(candidate)
        Row.new(
          key: "auto_revision_task:#{task.id}",
          record: task,
          action_candidate: candidate,
          auto_revision_task: task,
          business: task.business,
          title: task.title,
          expected_profit_yen: expected_value_yen,
          expected_hourly_value_yen: candidate&.expected_hourly_value_yen.to_i,
          priority_score: expected_value_yen,
          current_state: state_for_task(task),
          progress_percent: progress_for_task(task)[:percent],
          progress_label: progress_for_task(task)[:label],
          stuck_reason: stuck_reason_for_task(task),
          bucket: bucket_for_task(task),
          next_action_label: next_action_for_task(task)[:label],
          next_action_path: next_action_for_task(task)[:path],
          next_action_method: next_action_for_task(task)[:method],
          next_action_reason: next_action_for_task(task)[:reason],
          updated_at: task.updated_at,
          detail: detail_for_task(task)
        )
      end

      def row_for_candidate(candidate)
        automatic = candidate.business&.automatic_auto_revision?
        expected_value_yen = expected_value_yen_for(candidate)
        Row.new(
          key: "action_candidate:#{candidate.id}",
          record: candidate,
          action_candidate: candidate,
          auto_revision_task: nil,
          business: candidate.business,
          title: candidate.title,
          expected_profit_yen: expected_value_yen,
          expected_hourly_value_yen: candidate.expected_hourly_value_yen.to_i,
          priority_score: expected_value_yen,
          current_state: automatic ? "自動改修処理待ち" : "改修タスク化待ち",
          progress_percent: 10,
          progress_label: "Candidate",
          stuck_reason: automatic ? "自動改修ONです。次回表示またはDaily Runで自動処理します。" : "AutoRevisionTask未作成",
          bucket: :active,
          next_action_label: automatic ? "自動処理を待つ" : "改修開始",
          next_action_path: automatic ? nil : Rails.application.routes.url_helpers.create_task_owner_auto_revision_loop_candidate_path(candidate),
          next_action_method: automatic ? nil : :post,
          next_action_reason: automatic ? "自動改修ONのBusinessなので、Owner操作なしでGitHub Issue作成まで進みます。" : "自動改修OFFのBusinessなので、Ownerが改修開始を押すまで進めません。",
          updated_at: candidate.updated_at,
          detail: detail_for_candidate(candidate)
        )
      end

      def expected_value_sort_key(candidate, record)
        [
          -expected_value_yen_for(candidate).to_d,
          (record.created_at || Time.zone.at(0)).to_i,
          -record.id.to_i
        ]
      end

      def expected_value_yen_for(candidate)
        return 0 unless candidate

        @expected_value_yen_by_candidate_id ||= {}
        @expected_value_yen_by_candidate_id[candidate.id] ||= today_action_board.expected_value_yen_for(candidate).to_i
      end

      def today_action_board
        @today_action_board ||= Aicoo::TodayActionBoard.new(mode: "revenue")
      end

      def state_for_task(task)
        submission = task.codex_submission
        return "失敗" if submission&.workflow_status == "failed"
        return "PR作成済み" if submission&.pr_url.present?
        return "Codex作業待ち" if submission&.workflow_status == "codex_executed"
        return "Owner判断待ち" if task.owner_approval_required?

        case task.status
        when "draft", "waiting_approval" then "Codex準備前"
        when "approved", "ready_for_codex", "queued" then "Codex送信待ち"
        when "sent_to_codex" then "Codex作業待ち"
        when "running" then "Codex作業中"
        when "completed", "succeeded", "partial_succeeded" then result_state_for(task)
        when "failed" then "失敗"
        else task.status
        end
      end

      def next_action_for_task(task)
        routes = Rails.application.routes.url_helpers
        return action("判断する", routes.approve_owner_auto_revision_loop_task_path(task), :patch, task.approval_required_reason) if task.owner_approval_required?

        case task.status
        when "draft", "waiting_approval"
          action("Codex Prompt準備", routes.approve_owner_auto_revision_loop_task_path(task), :patch, "旧形式の待機タスクをCodex用プロンプト確認へ進めます。")
        when "approved", "ready_for_codex", "queued"
          action("GitHub Issueを作成", routes.create_github_issue_owner_auto_revision_loop_task_path(task), :post, "Codex Cloudで開けるGitHub Issueを作成します。")
        when "sent_to_codex"
          if task.codex_submission&.pr_url.present?
            action("実装結果を登録", nil, nil, "PR作成済みです。右側のフォームで実装結果を登録します。")
          else
            action("PR URLを登録", nil, nil, "GitHub Issueは作成済みです。Codex作業後のPR URLを登録します。")
          end
        when "running"
          action("実装済みにする", nil, nil, "右側の実装結果フォームから結果を登録してください。")
        when "completed", "succeeded", "partial_succeeded"
          if task.action_candidate&.action_result
            action("Learning状態を見る", nil, nil, "ActionResult登録済みです。評価ステータスをこのページで確認します。")
          else
            action("ActionResultを登録", nil, nil, "右側のActionResultフォームで学習データ化します。")
          end
        when "failed"
          action("再実行する", routes.retry_owner_auto_revision_loop_task_path(task), :patch, "失敗理由を確認し、再実行キューへ戻します。")
        else
          action("状態を確認", nil, nil, "このカード内で状態を確認してください。")
        end
      end

      def result_state_for(task)
        result = task.action_candidate&.action_result
        return "結果登録待ち" unless result
        return "完了" if result.evaluation_status == "evaluated"

        "Learning待ち"
      end

      def progress_for_task(task)
        case state_for_task(task)
        when "Owner判断待ち" then { percent: 15, label: "Owner" }
        when "Codex準備前" then { percent: 20, label: "Prompt" }
        when "Codex送信待ち" then { percent: 40, label: "Prompt" }
        when "Codex作業待ち" then { percent: 55, label: "Codex" }
        when "Codex作業中" then { percent: 65, label: "Implementation" }
        when "結果登録待ち" then { percent: 80, label: "Result" }
        when "Learning待ち" then { percent: 90, label: "Learning" }
        when "完了" then { percent: 100, label: "Done" }
        when "失敗" then { percent: 60, label: "Failed" }
        else { percent: 30, label: "Task" }
        end
      end

      def stuck_reason_for_task(task)
        case state_for_task(task)
        when "Owner判断待ち" then task.approval_required_reason
        when "Codex準備前" then "Codex Prompt準備待ち"
        when "Codex送信待ち" then "Codex用プロンプト未コピー"
        when "Codex作業待ち" then "GitHub Issue作成済み。Cloud Codex APIは未実装のためPR待ち"
        when "PR作成済み" then "PR確認または実装結果登録待ち"
        when "Codex作業待ち" then "Codex送信済み。実装開始記録待ち"
        when "Codex作業中" then task.auto_revision_executions.recent.first&.pull_request_url.present? ? "実装結果登録待ち" : "PR URL未登録"
        when "結果登録待ち" then "ActionResult未登録"
        when "Learning待ち" then "7日/14日/30日評価待ち"
        when "失敗" then task.error_message.presence || "失敗理由未記録"
        when "完了" then "完了"
        else "状態確認が必要"
        end
      end

      def bucket_for_task(task)
        return :failed if state_for_task(task) == "失敗"
        return :recent_completed if state_for_task(task) == "完了"

        :active
      end

      def action(label, path, method, reason)
        { label:, path:, method:, reason: }
      end

      def detail_for_task(task)
        {
          prompt: task.codex_prompt_markdown,
          github_issue_url: task.codex_submission&.github_issue_url,
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
