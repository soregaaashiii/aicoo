class Business < ApplicationRecord
  STATUSES = %w[idea researching building launched paused sold withdrawn].freeze

  has_many :action_candidates, dependent: :destroy
  has_many :action_results, dependent: :destroy
  has_many :action_candidate_score_snapshots, dependent: :destroy
  has_many :ai_evaluation_runs, dependent: :destroy
  has_many :data_sources, dependent: :destroy
  has_many :data_imports, through: :data_sources
  has_many :serp_analyses, dependent: :destroy
  has_many :revenue_events, dependent: :destroy
  has_many :business_metric_dailies, dependent: :destroy
  has_one :proxy_score_weight, dependent: :destroy
  has_many :proxy_score_weight_adjustment_logs, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true

  before_validation :set_default_status

  def current_month_revenue
    revenue_amount(current_month_range)
  end

  def current_month_expense
    expense_amount(current_month_range)
  end

  def current_month_profit
    current_month_revenue - current_month_expense
  end

  def cumulative_revenue
    revenue_amount
  end

  def cumulative_expense
    expense_amount
  end

  def cumulative_profit
    cumulative_revenue - cumulative_expense
  end

  def revenue_amount(range = nil)
    scoped_revenue_events(range).revenue.sum(:amount)
  end

  def expense_amount(range = nil)
    scoped_revenue_events(range).expense.sum(:amount)
  end

  def current_month_proxy_score
    proxy_score(current_month_range)
  end

  def recent_7d_proxy_score
    recent_proxy_score(7)
  end

  def recent_30d_proxy_score
    recent_proxy_score(30)
  end

  def cumulative_proxy_score
    proxy_score
  end

  def proxy_score(range = nil)
    scoped_business_metric_dailies(range).sum(&:proxy_score)
  end

  def current_month_metric_total(metric)
    metric_total(metric, current_month_range)
  end

  def cumulative_metric_total(metric)
    metric_total(metric)
  end

  def revenue_recorded?
    revenue_events.revenue.exists?
  end

  def evaluation_focus
    revenue_recorded? ? "profit" : "proxy_score"
  end

  def current_proxy_score_weight
    ProxyScoreWeight.for_business(self)
  end

  private

  def set_default_status
    self.status = "idea" if status.blank?
  end

  def current_month_range
    Date.current.beginning_of_month..Date.current.end_of_month
  end

  def recent_proxy_score(days)
    proxy_score((days - 1).days.ago.to_date..Date.current)
  end

  def scoped_revenue_events(range)
    scope = revenue_events
    range ? scope.where(occurred_on: range) : scope
  end

  def scoped_business_metric_dailies(range)
    scope = business_metric_dailies
    range ? scope.where(recorded_on: range) : scope
  end

  def metric_total(metric, range = nil)
    return 0 unless BusinessMetricDaily::SCORE_WEIGHTS.key?(metric.to_sym)

    scoped_business_metric_dailies(range).sum(metric)
  end
end
