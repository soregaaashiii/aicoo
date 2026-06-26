module Aicoo
  class CeoPriorityRanking
    SORT_MODES = %w[recommended revenue hourly learning].freeze

    Result = Data.define(:generated_at, :sort_mode, :items)
    Action = Data.define(:label, :method, :path, :style, :confirm_message)
    Item = Data.define(
      :rank,
      :task_key,
      :state_key,
      :state_label,
      :task,
      :queue_item,
      :summary,
      :action_candidate,
      :action_execution,
      :opportunity,
      :expected_profit_yen,
      :expected_hourly_value_yen,
      :learning_value_yen,
      :success_probability,
      :total_minutes,
      :recommendation_score,
      :recommendation_reasons,
      :actions
    )

    def initialize(tasks:, sort_mode: "recommended", queue_items: [], deferred_task_keys: [])
      @tasks = Array(tasks)
      @queue_items = Array(queue_items)
      @deferred_task_keys = Array(deferred_task_keys)
      @sort_mode = sort_mode.presence_in(SORT_MODES) || "recommended"
    end

    def call
      ranked = sorted_items.each.with_index(1).map { |item, index| rank_item(item, index) }
      Result.new(generated_at: Time.current, sort_mode:, items: ranked)
    end

    private

    attr_reader :tasks, :sort_mode, :queue_items, :deferred_task_keys

    def sorted_items
      items = tasks.map { |task| build_task_item(task) } + queue_items.map { |queue_item| build_queue_item(queue_item) }
      case sort_mode
      when "revenue"
        items.sort_by { |item| [ state_rank(item), -item.expected_profit_yen.to_i, item.summary.title ] }
      when "hourly"
        items.sort_by { |item| [ state_rank(item), -item.expected_hourly_value_yen.to_i, item.summary.title ] }
      when "learning"
        items.sort_by { |item| [ state_rank(item), -item.learning_value_yen.to_i, -item.recommendation_score.to_d, item.summary.title ] }
      else
        items.sort_by { |item| [ state_rank(item), -item.recommendation_score.to_d, item.summary.title ] }
      end
    end

    def build_task_item(task)
      execution = execution_for(task)
      candidate = candidate_for(task, execution)
      opportunity = opportunity_for(task)
      task_key = task_key_for(task)
      summary = CeoSummaryBuilder.new(task:, action_candidate: candidate, opportunity:).call
      expected_profit = summary.expected_profit_yen || candidate&.final_expected_value_yen || candidate&.expected_profit_yen || opportunity&.expected_value_yen
      minutes = summary.total_minutes.to_i
      hourly = candidate&.expected_hourly_value_yen || hourly_value(expected_profit, minutes)
      learning_value = candidate&.expected_learning_value_yen || opportunity_learning_value(opportunity)
      success_probability = summary.success_probability || candidate&.success_probability || opportunity_success_probability(opportunity)

      Item.new(
        rank: nil,
        task_key:,
        state_key: state_key_for(task, execution, task_key),
        state_label: state_label_for(task, execution, task_key),
        task:,
        queue_item: nil,
        summary:,
        action_candidate: candidate,
        action_execution: execution,
        opportunity:,
        expected_profit_yen: expected_profit.to_i,
        expected_hourly_value_yen: hourly.to_i,
        learning_value_yen: learning_value.to_i,
        success_probability: success_probability.to_d,
        total_minutes: minutes,
        recommendation_score: recommendation_score(task, candidate, opportunity, expected_profit, hourly, learning_value),
        recommendation_reasons: recommendation_reasons(summary, candidate, opportunity),
        actions: actions_for(task, candidate, execution, opportunity, task_key)
      )
    end

    def build_queue_item(queue_item)
      summary = queue_item_summary(queue_item)
      expected_profit = queue_item.expected_value_yen.to_i
      minutes = queue_item.metadata.to_h["expected_minutes"].to_i

      Item.new(
        rank: nil,
        task_key: nil,
        state_key: "later",
        state_label: "後でやる",
        task: nil,
        queue_item:,
        summary:,
        action_candidate: nil,
        action_execution: nil,
        opportunity: nil,
        expected_profit_yen: expected_profit,
        expected_hourly_value_yen: hourly_value(expected_profit, minutes).to_i,
        learning_value_yen: queue_item.metadata.to_h["learning_value_yen"].to_i,
        success_probability: 0.to_d,
        total_minutes: minutes,
        recommendation_score: queue_item.priority_score.to_d,
        recommendation_reasons: [ CeoSummaryBuilder.human_label(queue_item.reason) ],
        actions: [
          action("今日に戻す", :patch, Rails.application.routes.url_helpers.restore_owner_execution_queue_item_path(queue_item), "primary"),
          action("詳細を見る", :get, queue_item.target_path, "secondary")
        ]
      )
    end

    def candidate_for(task)
      candidate_for(task, execution_for(task))
    end

    def candidate_for(task, execution)
      if task.target_path.to_s.match?(%r{/action_candidates/\d+})
        ActionCandidate.find_by(id: task.target_path.to_s.split("/").last)
      elsif execution
        execution.action_candidate
      end
    end

    def execution_for(task)
      return unless task&.target_path.to_s.match?(%r{/action_executions/\d+})

      ActionExecution.find_by(id: task.target_path.to_s.split("/").last)
    end

    def rank_item(item, rank)
      Item.new(
        rank:,
        task_key: item.task_key,
        state_key: item.state_key,
        state_label: item.state_label,
        task: item.task,
        queue_item: item.queue_item,
        summary: item.summary,
        action_candidate: item.action_candidate,
        action_execution: item.action_execution,
        opportunity: item.opportunity,
        expected_profit_yen: item.expected_profit_yen,
        expected_hourly_value_yen: item.expected_hourly_value_yen,
        learning_value_yen: item.learning_value_yen,
        success_probability: item.success_probability,
        total_minutes: item.total_minutes,
        recommendation_score: item.recommendation_score,
        recommendation_reasons: item.recommendation_reasons,
        actions: item.actions
      )
    end

    def state_rank(item)
      case item.state_key
      when "running" then 0
      when "todo" then 1
      when "completed" then 2
      when "later" then 3
      else 1
      end
    end

    def state_key_for(task, execution, task_key)
      return "later" if deferred_task_keys.include?(task_key)
      return "running" if task.task_type == "action_execution_running" || execution&.status == "running"
      return "completed" if task.task_type == "action_result_registration" || execution&.status == "completed"

      "todo"
    end

    def state_label_for(task, execution, task_key)
      case state_key_for(task, execution, task_key)
      when "running" then "作業中"
      when "completed" then "完了済み"
      when "later" then "後でやる"
      else "未処理"
      end
    end

    def task_key_for(task)
      [ task.task_type, task.target_path, task.title ].join(":")
    end

    def opportunity_for(task)
      return unless task.task_type == "opportunity_review"

      OpportunityFocusQueue.new.call.items.find { |item| item.opportunity.title == task.title }&.opportunity
    end

    def hourly_value(expected_profit, minutes)
      return 0 if expected_profit.to_i.zero? || minutes.to_i.zero?

      (expected_profit.to_d / (minutes.to_d / 60)).round
    end

    def opportunity_learning_value(opportunity)
      return 0 unless opportunity

      (opportunity.expected_value_yen.to_i * opportunity.confidence.to_d / 100 * 0.15).round
    end

    def opportunity_success_probability(opportunity)
      return unless opportunity

      opportunity.confidence.to_d / 100
    end

    def recommendation_score(task, candidate, opportunity, expected_profit, hourly, learning_value)
      return candidate.final_score.to_d if candidate
      return opportunity.strategic_adjusted_score.to_d if opportunity&.strategic_adjusted_score.to_d.positive?

      priority_score(task) + (expected_profit.to_d / 1_000) + (hourly.to_d / 10_000) + (learning_value.to_d / 2_000)
    end

    def priority_score(task)
      case task.priority
      when "critical" then 100_000
      when "high" then 50_000
      when "medium" then 20_000
      else 5_000
      end
    end

    def recommendation_reasons(summary, candidate, opportunity)
      reasons = []
      reasons << "収益性が高い" if summary.expected_profit_yen.to_i >= 10_000
      reasons << "根拠データが揃っています" if evidence_score(candidate).to_d >= 60
      reasons << "今日すぐ着手できます" if candidate&.practicality_score.to_d >= 60 || summary.total_minutes.to_i <= 30
      reasons << "Business Playbookと一致しています" if playbook_match?(candidate)
      reasons << "学習価値があります" if candidate&.expected_learning_value_yen.to_i.positive? || opportunity&.learning_value_score.to_i.positive?
      reasons += summary.reason_lines.first(2)
      reasons.map { |reason| CeoSummaryBuilder.human_label(reason) }.compact_blank.uniq.first(5)
    end

    def evidence_score(candidate)
      candidate&.metadata.to_h.dig("evidence", "score")
    end

    def playbook_match?(candidate)
      return false unless candidate&.business&.business_playbook

      candidate.business.business_playbook.top_action_type == candidate.action_type ||
        candidate.metadata.to_h.dig("business_playbook", "coefficient").to_d > 1
    end

    def actions_for(task, candidate, execution, opportunity, task_key)
      routes = Rails.application.routes.url_helpers
      case state_key_for(task, execution, task_key)
      when "running"
        [
          action("完了する", :get, routes.action_execution_path(execution, anchor: "execution-result-form"), "primary"),
          action("中断する", :get, routes.action_execution_path(execution, outcome: "blocked", anchor: "execution-result-form"), "secondary")
        ]
      when "completed"
        [
          action("結果登録へ", :get, routes.new_action_result_path(action_execution_id: execution&.id), "primary"),
          action("詳細を見る", :get, detail_path_for(task, candidate, execution, opportunity), "secondary")
        ]
      when "later"
        [
          action("今日に戻す", :patch, routes.restore_owner_focus_path(task_key:, sort: sort_mode), "primary"),
          action("詳細を見る", :get, detail_path_for(task, candidate, execution, opportunity), "secondary")
        ]
      else
        [
          todo_primary_action(task, candidate, execution, opportunity),
          action("詳細を見る", :get, detail_path_for(task, candidate, execution, opportunity), "secondary"),
          todo_later_action(task_key)
        ].compact
      end
    end

    def todo_primary_action(task, candidate, execution, opportunity)
      routes = Rails.application.routes.url_helpers
      return action("作業開始", :patch, routes.start_action_execution_path(execution), "primary") if execution
      return action("作業開始", :post, routes.focus_convert_to_candidate_owner_opportunity_path(opportunity), "primary") if opportunity
      return action("作業開始", :post, routes.generate_codex_prompt_draft_action_candidate_path(candidate), "primary") if candidate

      quick_action = task.quick_actions.find { |item| item.method.to_s != "get" && item.style != "danger" }
      quick_action && action(primary_label_for(task, quick_action), quick_action.method, quick_action.path, "primary", quick_action.confirm_message)
    end

    def primary_label_for(task, quick_action)
      case task.task_type
      when "daily_run_failure", "daily_run_partial_failed"
        "再実行する"
      when "daily_run_step_recovery"
        "復旧する"
      when "daily_run_step_failure", "daily_run_recovery_attention"
        "確認する"
      when "analysis_review", "explore_daily_routine", "explore_signal_review"
        "確認する"
      else
        CeoSummaryBuilder.human_label(quick_action.label).presence || "作業開始"
      end
    end

    def detail_path_for(task, candidate, execution, opportunity)
      routes = Rails.application.routes.url_helpers
      return routes.owner_opportunity_path(opportunity) if opportunity
      return routes.action_execution_path(execution) if execution
      return routes.action_execution_path(candidate.action_execution) if candidate&.action_execution

      task.target_path
    end

    def todo_later_action(task_key)
      action("後でやる", :patch, Rails.application.routes.url_helpers.defer_owner_focus_path(task_key:, sort: sort_mode), "secondary")
    end

    def queue_item_summary(queue_item)
      CeoSummaryBuilder::Summary.new(
        title: CeoSummaryBuilder.human_label(queue_item.title),
        reason_lines: [ CeoSummaryBuilder.human_label(queue_item.reason) ],
        work_lines: [ "今日に戻すか、詳細を確認する" ],
        target_label: queue_item.business&.name,
        time_lines: [],
        total_minutes: queue_item.metadata.to_h["expected_minutes"].to_i,
        expected_profit_yen: queue_item.expected_value_yen.to_i,
        roi: nil,
        success_probability: nil,
        completion_criteria: [ "今日に戻すか判断する" ],
        start_label: "今日に戻す",
        codex_label: nil,
        empty?: false
      )
    end

    def action(label, method, path, style, confirm_message = nil)
      Action.new(label:, method:, path:, style:, confirm_message:)
    end
  end
end
