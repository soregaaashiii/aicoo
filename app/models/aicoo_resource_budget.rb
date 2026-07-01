class AicooResourceBudget < ApplicationRecord
  validates :codex_concurrent_limit, :codex_waiting_limit, :build_queue_limit,
            :deploy_queue_limit, :render_service_limit, :simultaneous_mvp_limit,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :monthly_ai_budget_yen, :current_month_ai_spend_yen,
            numericality: { greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!
  end

  def remaining_budget_yen
    monthly_ai_budget_yen.to_d - current_month_ai_spend_yen.to_d
  end

  def budget_available?(estimated_cost_yen)
    return true if monthly_ai_budget_yen.to_d.zero?

    remaining_budget_yen >= estimated_cost_yen.to_d
  end

  def codex_waiting_count
    AutoRevisionTask.codex_queue.count
  end

  def codex_running_count
    AutoRevisionTask.where(status: "running").count
  end

  def build_queue_count
    AutoBuildTask.active.count
  end

  def deploy_queue_count
    AutoRevisionExecution.where(status: %w[queued running sent_to_codex]).count
  end

  def render_service_count
    BusinessService.where.not(render_service: [ nil, "" ]).distinct.count(:render_service)
  end

  def current_mvp_count
    Business.real_businesses.where(lifecycle_stage: "mvp").count
  end

  def codex_capacity_available?
    codex_running_count < codex_concurrent_limit && codex_waiting_count < codex_waiting_limit
  end

  def build_capacity_available?
    build_queue_count < build_queue_limit && current_mvp_count < simultaneous_mvp_limit
  end

  def deploy_capacity_available?
    deploy_queue_count < deploy_queue_limit
  end

  def render_capacity_available?
    render_service_limit.zero? || render_service_count < render_service_limit
  end

  def resource_available_for?(estimated_cost_yen)
    auto_build_enabled? &&
      codex_capacity_available? &&
      build_capacity_available? &&
      deploy_capacity_available? &&
      render_capacity_available? &&
      budget_available?(estimated_cost_yen)
  end
end
