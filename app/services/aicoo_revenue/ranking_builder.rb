module AicooRevenue
  class RankingBuilder
    DEFAULT_AVAILABLE_MINUTES = 180
    DEFAULT_AVAILABLE_BUDGET_YEN = 0
    DEFAULT_HOURLY_COST_YEN = 1_226
    DEFAULT_NEGLECT_ALERT_DAYS = 14
    NEGLECT_DONE_STATUSES = %w[done failed rejected success].freeze
    SOURCES = %w[all candidate experiment action_candidate].freeze

    Row = Data.define(
      :title,
      :source,
      :source_id,
      :status,
      :experiment_type,
      :market_category,
      :expected_90d_profit_yen,
      :success_probability,
      :manual_neglect_loss_90d_yen,
      :estimated_neglect_loss_90d_yen,
      :neglect_loss_auto_generated,
      :neglect_loss_90d_yen,
      :neglect_loss_reason,
      :revenue_total_value_yen,
      :estimated_work_minutes,
      :budget_yen,
      :time_cost_yen,
      :revenue_score,
      :expected_hourly_profit,
      :roi_score,
      :neglect_alert,
      :neglected_days,
      :neglect_alert_reason,
      :url
    )

    Result = Data.define(
      :revenue_rankings,
      :hourly_rankings,
      :roi_rankings,
      :neglect_alerts,
      :available_minutes,
      :available_budget_yen,
      :hourly_cost_yen,
      :source
    )

    def initialize(available_minutes: DEFAULT_AVAILABLE_MINUTES, available_budget_yen: DEFAULT_AVAILABLE_BUDGET_YEN, source: "all")
      @available_minutes = available_minutes.presence&.to_i || DEFAULT_AVAILABLE_MINUTES
      @available_budget_yen = available_budget_yen.presence&.to_i || DEFAULT_AVAILABLE_BUDGET_YEN
      @hourly_cost_yen = AicooLabSetting.current&.hourly_cost_yen || DEFAULT_HOURLY_COST_YEN
      @source = SOURCES.include?(source) ? source : "all"
    end

    def call
      source_rows = normalized_rows.select { |row| source_match?(row) }
      rows = source_rows.select { |row| eligible?(row) }

      Result.new(
        revenue_rankings: rows.sort_by { |row| -sortable_score(row.revenue_score) },
        hourly_rankings: rows.sort_by { |row| -sortable_score(row.expected_hourly_profit) },
        roi_rankings: rows.sort_by { |row| -sortable_score(row.roi_score) },
        neglect_alerts: source_rows.select(&:neglect_alert).sort_by { |row| [ -row.neglected_days.to_i, -sortable_score(row.revenue_score) ] },
        available_minutes:,
        available_budget_yen:,
        hourly_cost_yen:,
        source:
      )
    end

    private

    attr_reader :available_minutes, :available_budget_yen, :hourly_cost_yen, :source

    def normalized_rows
      candidate_rows + experiment_rows + action_candidate_rows
    end

    def candidate_rows
      AicooLabExperimentCandidate.find_each.map do |candidate|
        build_row(
          record: candidate,
          source: "candidate",
          url: Rails.application.routes.url_helpers.admin_aicoo_lab_candidate_path(candidate)
        )
      end
    end

    def experiment_rows
      AicooLabExperiment.find_each.map do |experiment|
        build_row(
          record: experiment,
          source: "experiment",
          url: Rails.application.routes.url_helpers.admin_aicoo_lab_experiment_path(experiment)
        )
      end
    end

    def action_candidate_rows
      ActionCandidate.includes(:business).find_each.filter_map do |action_candidate|
        build_row_from_action_candidate(action_candidate)
      end
    end

    def build_row(record:, source:, url:)
      expected_profit = record.expected_90d_profit_yen
      probability = record.success_probability
      minutes = record.estimated_work_minutes
      budget = record.budget_yen
      time_cost = time_cost_for(minutes)
      neglect_values = neglect_values_for(record)
      neglect_loss = neglect_values.adopted_loss
      total_value = revenue_total_value(expected_profit, probability, neglect_loss)
      alert = neglect_alert_for(record, neglect_loss)

      Row.new(
        title: record.title,
        source:,
        source_id: record.id,
        status: record.status,
        experiment_type: record.experiment_type,
        market_category: record.market_category,
        expected_90d_profit_yen: expected_profit,
        success_probability: probability,
        manual_neglect_loss_90d_yen: neglect_values.manual_loss,
        estimated_neglect_loss_90d_yen: neglect_values.estimated_loss,
        neglect_loss_auto_generated: neglect_values.auto_generated,
        neglect_loss_90d_yen: neglect_loss,
        neglect_loss_reason: record.neglect_loss_reason,
        revenue_total_value_yen: total_value,
        estimated_work_minutes: minutes,
        budget_yen: budget,
        time_cost_yen: time_cost,
        revenue_score: ratio(total_value, time_cost + budget.to_i),
        expected_hourly_profit: ratio(total_value, minutes.to_d / 60),
        roi_score: ratio(total_value, budget.to_i),
        neglect_alert: alert.enabled,
        neglected_days: alert.neglected_days,
        neglect_alert_reason: alert.reason,
        url:
      )
    end

    def build_row_from_action_candidate(action_candidate)
      expected_profit = action_candidate.expected_profit_yen
      probability = normalized_probability(action_candidate.success_probability)
      return if expected_profit.blank? || probability.blank?

      minutes = action_candidate.expected_hours.to_d * 60
      budget = action_candidate.cost_yen || 0
      time_cost = time_cost_for(minutes)
      neglect_values = neglect_values_for(action_candidate)
      neglect_loss = neglect_values.adopted_loss
      total_value = revenue_total_value(expected_profit, probability, neglect_loss)
      alert = neglect_alert_for(action_candidate, neglect_loss)

      Row.new(
        title: action_candidate.title,
        source: "action_candidate",
        source_id: action_candidate.id,
        status: action_candidate.status,
        experiment_type: action_candidate.action_type,
        market_category: action_candidate.business&.name,
        expected_90d_profit_yen: expected_profit,
        success_probability: probability,
        manual_neglect_loss_90d_yen: neglect_values.manual_loss,
        estimated_neglect_loss_90d_yen: neglect_values.estimated_loss,
        neglect_loss_auto_generated: neglect_values.auto_generated,
        neglect_loss_90d_yen: neglect_loss,
        neglect_loss_reason: action_candidate.neglect_loss_reason,
        revenue_total_value_yen: total_value,
        estimated_work_minutes: minutes,
        budget_yen: budget,
        time_cost_yen: time_cost,
        revenue_score: ratio(total_value, time_cost + budget.to_i),
        expected_hourly_profit: ratio(total_value, minutes.to_d / 60),
        roi_score: ratio(total_value, budget.to_i),
        neglect_alert: alert.enabled,
        neglected_days: alert.neglected_days,
        neglect_alert_reason: alert.reason,
        url: Rails.application.routes.url_helpers.action_candidate_path(action_candidate)
      )
    end

    def eligible?(row)
      row.expected_90d_profit_yen.present? &&
        row.success_probability.present? &&
        row.estimated_work_minutes.to_i <= available_minutes &&
        row.budget_yen.to_i <= available_budget_yen
    end

    def source_match?(row)
      source == "all" || row.source == source
    end

    def time_cost_for(minutes)
      minutes.to_d / 60 * hourly_cost_yen
    end

    def ratio(numerator, denominator)
      return Float::INFINITY if denominator.zero? && numerator.positive?
      return 0.to_d if denominator.zero?

      numerator / denominator
    end

    def normalized_probability(probability)
      return if probability.blank?

      value = probability.to_d
      value > 1 ? value / 100 : value
    end

    def revenue_total_value(expected_profit, probability, neglect_loss)
      (expected_profit.to_d * probability.to_d) + neglect_loss.to_i
    end

    def neglect_values_for(record)
      estimation = NeglectLossEstimator.new(record).estimate_and_store!
      manual_loss = record.neglect_loss_90d_yen.to_i
      estimated_loss = estimation.estimated_neglect_loss_90d_yen.to_i

      NeglectValues.new(
        manual_loss:,
        estimated_loss:,
        auto_generated: estimation.auto_generated,
        adopted_loss: manual_loss.positive? ? manual_loss : estimated_loss
      )
    end

    def neglect_alert_for(record, neglect_loss)
      neglected_days = ((Time.current - record.updated_at) / 1.day).floor
      enabled = neglect_loss.to_i.positive? &&
                !NEGLECT_DONE_STATUSES.include?(record.status) &&
                neglected_days >= DEFAULT_NEGLECT_ALERT_DAYS
      reason =
        if enabled
          record.neglect_loss_reason.presence ||
            "放置損失があり、#{neglected_days}日間更新されていません。"
        end

      NeglectAlert.new(enabled, neglected_days, reason)
    end

    def sortable_score(value)
      value.infinite? ? Float::INFINITY : value.to_d
    end

    NeglectAlert = Data.define(:enabled, :neglected_days, :reason)
    NeglectValues = Data.define(:manual_loss, :estimated_loss, :auto_generated, :adopted_loss)
  end
end
