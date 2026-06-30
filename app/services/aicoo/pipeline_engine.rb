module Aicoo
  class PipelineEngine
    STAGES = AicooPipelineRun::STAGES

    def self.sync_idea_pipeline_scope(items)
      Array(items).index_with { |item| new(item).call }
    end

    def initialize(subject)
      @subject = subject
    end

    def call
      run = find_or_initialize_run
      gates = Aicoo::Pipeline::GateEngine.new(subject).call
      waiting = Aicoo::Pipeline::WaitingEngine.new(subject).call
      pivot = Aicoo::Pipeline::PivotEngine.new(subject).call
      estimated_cost = estimated_cost_yen
      budget = Aicoo::Pipeline::BudgetEngine.new(subject, estimated_cost_yen: estimated_cost).call
      states = build_stage_states(gates:, waiting:, pivot:, budget:)
      current_stage = first_open_stage(states)
      stage_entered_at = stage_entered_at_for(run, current_stage)
      states[current_stage] = states[current_stage].to_h.merge("started_at" => stage_entered_at.iso8601) if current_stage
      status = pipeline_status(states:, current_stage:, waiting:, budget:)

      run.assign_attributes(
        pipeline_type: pipeline_type,
        business: business,
        idea_pipeline_item: idea_item,
        aicoo_lab_landing_page: landing_page,
        status:,
        current_stage:,
        next_stage: next_stage_after(current_stage),
        started_at: run.started_at || subject_created_at,
        finished_at: finished_at_for(status),
        retry_count: retry_count(states),
        last_error: last_error(states),
        confidence: confidence,
        expected_value_yen: expected_value_yen,
        estimated_cost_yen: estimated_cost,
        actual_cost_yen: actual_cost_yen,
        waiting_until: waiting["waiting_until"],
        waiting_reason: waiting["reason"],
        halted_reason: halted_reason(status:, states:, budget:),
        pivot_decision: pivot["decision"],
        stage_states: states,
        gate_snapshot: gates,
        budget_snapshot: budget,
        metadata: run.metadata.to_h.merge(
          "waiting" => waiting,
          "pivot" => pivot,
          "pipeline_events" => pipeline_events(run, gates),
          "stage_entered_at" => stage_entered_at.iso8601,
          "synced_at" => Time.current.iso8601
        )
      )
      run.retry_schedule = Aicoo::Pipeline::RetryEngine.new(run).call
      run.save!
      run
    end

    private

    attr_reader :subject

    def find_or_initialize_run
      if idea_item
        AicooPipelineRun.find_or_initialize_by(pipeline_type: "idea_pipeline", idea_pipeline_item: idea_item)
      elsif business
        AicooPipelineRun.find_or_initialize_by(pipeline_type: "business", business:)
      else
        raise ArgumentError, "Unsupported pipeline subject: #{subject.class.name}"
      end
    end

    def pipeline_type
      idea_item ? "idea_pipeline" : "business"
    end

    def idea_item
      subject if subject.is_a?(IdeaPipelineItem)
    end

    def business
      idea_item&.business || (subject if subject.is_a?(Business))
    end

    def landing_page
      idea_item&.aicoo_lab_landing_page || business&.aicoo_lab_landing_pages&.order(updated_at: :desc)&.first
    end

    def build_stage_states(gates:, waiting:, pivot:, budget:)
      STAGES.index_with do |stage|
        send("#{stage}_state", gates:, waiting:, pivot:, budget:)
      end
    end

    def discovery_state(**)
      done_state("Idea/Businessを発見済みです。", started_at: subject_created_at, finished_at: subject_created_at)
    end

    def score_state(**)
      return done_state("期待値評価済みです。", finished_at: idea_item.evaluated_at, confidence: confidence) if idea_item&.evaluated_at

      open_state("期待値評価待ちです。")
    end

    def serp_state(gates:, **)
      gate = gates.fetch("serp")
      return skipped_state(gate["message"], reason: gate["reason"], finished_at: idea_item&.serp_evaluated_at) if idea_item&.serp_status == "serp_skipped"
      return running_state("SERP実行中です。") if idea_item&.serp_status == "serp_running"
      return done_state("SERP評価済みです。", finished_at: idea_item&.serp_evaluated_at, confidence: confidence) if idea_item&.serp_passed? || idea_item&.serp_snapshot.to_h["status"].present?

      gate["status"] == "skipped" ? skipped_state(gate["message"], reason: gate["reason"]) : open_state(gate["message"], reason: gate["reason"])
    end

    def lp_state(gates:, **)
      return done_state("LP生成済みです。", finished_at: idea_item&.lp_generated_at || landing_page&.created_at) if landing_page

      gate = gates.fetch("lp")
      gate["status"] == "blocked" ? blocked_state(gate["message"], reason: gate["reason"]) : open_state(gate["message"], reason: gate["reason"])
    end

    def publish_state(gates:, **)
      return done_state("公開済みです。", finished_at: landing_page&.published_at || idea_item&.published_at) if landing_page&.publicly_visible?

      gate = gates.fetch("publish")
      gate["status"] == "open" ? open_state(gate["message"], reason: gate["reason"]) : waiting_state(gate["message"], reason: gate["reason"])
    end

    def measure_state(waiting:, **)
      return done_state("反応計測済みです。", finished_at: idea_item.learning_evaluated_at) if idea_item&.learning_evaluated_at
      return waiting_state(waiting["message"], reason: waiting["reason"], waiting_until: waiting["waiting_until"]) if waiting["waiting"]

      open_state("PV/CTA/CVを計測します。")
    end

    def improve_state(gates:, **)
      return done_state("改善判断済みです。", finished_at: idea_item.mvp_decided_at) if idea_item&.mvp_decided_at

      gate = gates.fetch("improve")
      return approval_state(gate["message"], reason: gate["reason"]) if gate["status"] == "approval"
      return waiting_state(gate["message"], reason: gate["reason"]) if gate["status"] == "waiting"

      open_state(gate["message"], reason: gate["reason"])
    end

    def deploy_state(gates:, **)
      gate = gates.fetch("deploy")
      return done_state(gate["message"], reason: gate["reason"]) if gate["status"] == "done"
      return open_state(gate["message"], reason: gate["reason"]) if gate["status"] == "open"
      return approval_state(gate["message"], reason: gate["reason"]) if gate["status"] == "approval"

      waiting_state(gate["message"], reason: gate["reason"])
    end

    def pipeline_events(run, gates)
      events = Array(run.metadata.to_h["pipeline_events"])
      deploy_event = gates.dig("deploy", "event")
      return events unless deploy_event.present?

      event = {
        "type" => deploy_event,
        "stage" => "deploy",
        "recorded_at" => Time.current.iso8601
      }
      events.last == event.except("recorded_at") ? events : events.push(event).last(50)
    end

    def learning_state(gates:, **)
      return done_state("学習反映済みです。", finished_at: idea_item.learning_evaluated_at) if idea_item&.learning_evaluated_at

      gate = gates.fetch("learning")
      gate["status"] == "open" ? open_state(gate["message"], reason: gate["reason"]) : waiting_state(gate["message"], reason: gate["reason"])
    end

    def decision_state(pivot:, **)
      return done_state(pivot["reason"], reason: pivot["decision"], finished_at: idea_item.mvp_decided_at) if idea_item&.mvp_decided_at

      waiting_state("Learning後にContinue / Pivot / Endを判断します。", reason: "learning_required")
    end

    def first_open_stage(states)
      STAGES.find { |stage| states.dig(stage, "status").in?(%w[open running waiting approval_waiting blocked retry_waiting budget_blocked]) } || "decision"
    end

    def pipeline_status(states:, current_stage:, waiting:, budget:)
      return "budget_blocked" if budget["over_budget"]
      current_status = states.dig(current_stage, "status")
      return "completed" if states.values.all? { |state| state["status"].in?(%w[done skipped]) }
      return "waiting" if waiting["waiting"] && current_stage == "measure"
      return "approval_waiting" if current_status == "approval_waiting"
      return "blocked" if current_status == "blocked"
      return "retry_waiting" if current_status == "retry_waiting"

      "running"
    end

    def next_stage_after(stage)
      index = STAGES.index(stage)
      return if index.blank?

      STAGES[index + 1]
    end

    def stage_entered_at_for(run, current_stage)
      previous_stage = run.current_stage
      previous_entered_at = parse_time(run.metadata.to_h["stage_entered_at"])
      return previous_entered_at if previous_stage == current_stage && previous_entered_at

      Time.current
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def subject_created_at
      subject.respond_to?(:created_at) ? subject.created_at : Time.current
    end

    def finished_at_for(status)
      Time.current if status.in?(%w[completed ended])
    end

    def retry_count(states)
      states.values.sum { |state| state["retry_count"].to_i }
    end

    def last_error(states)
      states.values.filter_map { |state| state["last_error"].presence }.first
    end

    def halted_reason(status:, states:, budget:)
      return "monthly_budget_exceeded" if status == "budget_blocked"

      states.dig(first_open_stage(states), "reason")
    end

    def confidence
      return idea_item.final_score.to_d if idea_item&.final_score

      business&.business_playbook&.confidence_score.to_d
    end

    def expected_value_yen
      return idea_item.expected_profit_yen.to_d if idea_item&.expected_profit_yen

      business&.current_month_profit.to_d
    end

    def estimated_cost_yen
      DataSourceCostProfile.find_by(source_key: "serp")&.average_cost_yen.to_d || 0.to_d
    end

    def actual_cost_yen
      DataSourceCostProfile.find_by(source_key: "serp")&.monthly_spend_yen.to_d || 0.to_d
    end

    def done_state(message, reason: nil, started_at: nil, finished_at: nil, confidence: nil)
      base_state("done", message, reason:, started_at:, finished_at:, confidence:)
    end

    def skipped_state(message, reason: nil, finished_at: nil)
      base_state("skipped", message, reason:, finished_at:)
    end

    def open_state(message, reason: nil)
      base_state("open", message, reason:)
    end

    def running_state(message, reason: nil)
      base_state("running", message, reason:)
    end

    def waiting_state(message, reason: nil, waiting_until: nil)
      base_state("waiting", message, reason:, waiting_until:)
    end

    def approval_state(message, reason: nil)
      base_state("approval_waiting", message, reason:)
    end

    def blocked_state(message, reason: nil)
      base_state("blocked", message, reason:, last_error: message)
    end

    def base_state(status, message, reason: nil, started_at: nil, finished_at: nil, waiting_until: nil, confidence: nil, last_error: nil)
      {
        "status" => status,
        "message" => message,
        "reason" => reason,
        "started_at" => started_at&.iso8601,
        "finished_at" => finished_at&.iso8601,
        "duration" => duration_seconds(started_at, finished_at),
        "retry_count" => 0,
        "waiting_until" => waiting_until,
        "confidence" => confidence&.to_s,
        "expected_value" => expected_value_yen.to_s,
        "estimated_cost" => estimated_cost_yen.to_s,
        "actual_cost" => actual_cost_yen.to_s,
        "last_error" => last_error
      }.compact
    end

    def duration_seconds(started_at, finished_at)
      return unless started_at && finished_at

      (finished_at - started_at).to_i
    end
  end
end
