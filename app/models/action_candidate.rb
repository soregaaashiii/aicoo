class ActionCandidate < ApplicationRecord
  ACTION_TYPES = %w[
    seo_article
    seo_improvement
    serp_research
    market_research
    build_lp
    build_mvp
    ui_improvement
    feature_development
    sales
    outsourcing
    automation
    pivot
    withdraw
    sell
    data_preparation
    other
  ].freeze

  STATUSES = %w[idea pending approved executor_queued in_progress done rejected archived].freeze
  INACTIVE_STATUSES = %w[archived rejected done].freeze
  GENERATION_SOURCES = %w[manual seed ai_business ai_cross_business ai_reevaluation].freeze

  belongs_to :business
  has_one :action_result, dependent: :destroy
  has_many :action_candidate_score_snapshots, dependent: :destroy

  before_validation :set_defaults
  before_save :calculate_scores

  validates :title, presence: true
  validates :action_type, inclusion: { in: ACTION_TYPES }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :generation_source, inclusion: { in: GENERATION_SOURCES }, allow_blank: true
  validates :success_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :strategic_value_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :risk_reduction_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :data_confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :priority_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :expected_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :immediate_value_yen, numericality: { only_integer: true }, allow_nil: true
  validates :neglect_loss_90d_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :estimated_neglect_loss_90d_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expected_revenue_value_yen, :expected_learning_value_yen, :expected_total_value_yen,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :final_expected_value_yen, :final_confidence_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_expected_value, -> { includes(:business).order(Arel.sql("expected_hourly_value_yen DESC NULLS LAST, expected_profit_yen DESC NULLS LAST")) }
  scope :by_recommendation, -> { includes(:business).order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST")) }
  scope :active_for_ranking, -> { where.not(status: INACTIVE_STATUSES) }
  scope :approved_queue, -> { where(status: "approved").order(approved_at: :desc, expected_total_value_yen: :desc) }

  def data_preparation?
    action_type == "data_preparation"
  end

  def unfinished_executor_task
    return unless data_preparation?

    AicooExecutorTask.unfinished_for_action_candidate(self)
  end

  def approve!(approved_by: nil)
    update!(status: "approved", approved_at: Time.current, approved_by:)
  end

  def mark_executor_queued!
    update!(status: "executor_queued", executor_queued_at: Time.current)
  end

  def revenue_ratio
    value_ratio(expected_revenue_value_yen)
  end

  def learning_ratio
    return 0 if expected_total_value_yen.to_i.zero?

    100 - revenue_ratio
  end

  private

  def set_defaults
    self.action_type = "other" if action_type.blank?
    self.status = "idea" if status.blank?
    self.generation_source = "manual" if generation_source.blank?
    self.success_probability = 0 if success_probability.nil?
    self.immediate_value_yen = 0 if immediate_value_yen.nil?
    self.strategic_value_score = 0 if strategic_value_score.nil?
    self.risk_reduction_score = 0 if risk_reduction_score.nil?
    self.confidence_score = 0 if confidence_score.nil?
    self.data_confidence_score = 20 if data_confidence_score.nil?
    self.priority_score = 0 if priority_score.nil?
    self.neglect_loss_90d_yen = 0 if neglect_loss_90d_yen.nil?
    self.estimated_neglect_loss_90d_yen = 0 if estimated_neglect_loss_90d_yen.nil?
    self.expected_revenue_value_yen = 0 if expected_revenue_value_yen.nil?
    self.expected_learning_value_yen = 0 if expected_learning_value_yen.nil?
    self.expected_total_value_yen = 0 if expected_total_value_yen.nil?
    self.final_expected_value_yen = 0 if final_expected_value_yen.nil?
    self.final_confidence_score = 0 if final_confidence_score.nil?
  end

  def calculate_scores
    self.expected_profit_yen = (immediate_value_yen.to_d * success_probability.to_d).round
    self.expected_hourly_value_yen = calculate_expected_hourly_value
    self.roi = calculate_roi
    self.final_score = calculate_final_score
    self.expected_revenue_value_yen = calculate_expected_revenue_value
    self.expected_learning_value_yen = LearningValueCalculator.new(self).value_yen
    self.expected_total_value_yen = expected_revenue_value_yen.to_i + expected_learning_value_yen.to_i
    apply_meta_evaluation
  end

  def calculate_expected_hourly_value
    return nil if expected_hours.blank? || expected_hours.to_d.zero?

    (expected_profit_yen.to_d / expected_hours.to_d).round
  end

  def calculate_roi
    return nil if cost_yen.blank? || cost_yen.to_d.zero?

    expected_profit_yen.to_d / cost_yen.to_d
  end

  def calculate_final_score
    hourly_value = expected_hourly_value_yen || 0
    strategic_value = strategic_value_score.to_i * 100
    risk_reduction_value = risk_reduction_score.to_i * 100

    (hourly_value * 0.7) + (strategic_value * 0.2) + (risk_reduction_value * 0.1)
  end

  def calculate_expected_revenue_value
    [
      expected_profit_yen.to_i,
      neglect_loss_90d_yen.to_i,
      estimated_neglect_loss_90d_yen.to_i
    ].sum
  end

  def value_ratio(value)
    return 0 if expected_total_value_yen.to_i.zero?

    (value.to_d / expected_total_value_yen.to_d * 100).round
  end

  def apply_meta_evaluation
    result = AicooMetaEvaluator::MetaEvaluator.new(self).call
    self.final_expected_value_yen = result.final_expected_value_yen
    self.final_confidence_score = result.final_confidence_score
    self.metadata = metadata.to_h.merge("evaluator_breakdown" => result.evaluator_breakdown)
  end
end
