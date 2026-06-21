class AicooLabExperiment < ApplicationRecord
  EXPERIMENT_TYPES = %w[lp seo saas chrome_extension ai_tool directory_site ui_ux market_test other].freeze
  ACQUISITION_CHANNELS = %w[seo sns ads direct referral unknown].freeze
  STATUSES = %w[draft preview_ready approval_pending running paused success failed reevaluate].freeze
  APPROVAL_STATUSES = %w[not_required pending approved rejected].freeze
  PREDICTED_SCORING_DAYS = {
    "lp" => 30,
    "ads" => 7,
    "seo" => 90,
    "saas" => 60,
    "chrome_extension" => 30,
    "ai_tool" => 30,
    "directory_site" => 90,
    "ui_ux" => 30,
    "market_test" => 30,
    "other" => 60
  }.freeze

  has_many :aicoo_lab_predictions, dependent: :destroy
  has_many :aicoo_lab_results, dependent: :destroy
  has_many :aicoo_lab_error_metrics, dependent: :destroy
  has_one :aicoo_lab_landing_page, dependent: :destroy

  before_validation :set_defaults
  before_save :calculate_scores

  validates :title, presence: true
  validates :experiment_type, inclusion: { in: EXPERIMENT_TYPES }
  validates :acquisition_channel, inclusion: { in: ACQUISITION_CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :success_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :expected_90d_profit_yen, :budget_yen, :actual_cost_yen, :estimated_work_minutes, :actual_work_minutes,
            :sample_pv_threshold, :current_pv, :lp_word_count, :cta_count, :assumed_price_yen, :development_minutes,
            :feature_count, :neglect_loss_90d_yen, :estimated_neglect_loss_90d_yen,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_lab_priority, -> { order(Arel.sql("lab_priority_score DESC NULLS LAST, expected_value_score DESC NULLS LAST")) }
  scope :approval_pending, -> { where(approval_status: "pending").by_lab_priority }
  scope :approved_not_started, -> { where(approval_status: "approved").where.not(status: %w[running success failed]).by_lab_priority }
  scope :review_queue, lambda {
    where(status: "preview_ready", approval_status: %w[not_required pending]).or(where(approval_status: "pending")).by_lab_priority
  }

  def calibration_score
    scores = aicoo_lab_error_metrics.filter_map(&:calibration_score)
    return nil if scores.empty?

    scores.sum / scores.size
  end

  def mark_status!(next_status)
    update!(status_attributes_for(next_status))
  end

  def recalculate_error_metrics!
    AicooLabErrorMetric.recalculate_for_experiment!(self)
  end

  private

  def set_defaults
    self.experiment_type = "other" if experiment_type.blank?
    self.acquisition_channel = "unknown" if acquisition_channel.blank?
    self.status = "draft" if status.blank?
    self.approval_status = "not_required" if approval_status.blank?
    self.learning_value_score = 1.0 if learning_value_score.blank?
    self.sample_pv_threshold = AicooLabSetting.current.minimum_sample_pv if sample_pv_threshold.blank?
    self.current_pv = 0 if current_pv.blank?
    self.expected_90d_profit_yen = 0 if expected_90d_profit_yen.blank?
    self.success_probability = 0 if success_probability.blank?
    self.budget_yen = 0 if budget_yen.blank?
    self.estimated_work_minutes = 0 if estimated_work_minutes.blank?
    self.neglect_loss_90d_yen = 0 if neglect_loss_90d_yen.blank?
    self.estimated_neglect_loss_90d_yen = 0 if estimated_neglect_loss_90d_yen.blank?
  end

  def calculate_scores
    setting = AicooLabSetting.current
    time_cost_yen = estimated_work_minutes.to_d / 60 * setting.hourly_cost_yen
    denominator = time_cost_yen + budget_yen.to_i

    self.expected_value_score = denominator.positive? ? expected_90d_profit_yen.to_d * success_probability.to_d / denominator : nil
    self.scoring_speed_score = 1.to_d / predicted_scoring_days
    self.lab_priority_score = expected_value_score ? expected_value_score * scoring_speed_score : nil
  end

  def predicted_scoring_days
    PREDICTED_SCORING_DAYS.fetch(experiment_type, 60)
  end

  def status_attributes_for(next_status)
    attributes = { status: next_status }
    now = Time.current

    case next_status
    when "approval_pending"
      attributes[:approval_status] = "pending"
    when "running"
      attributes[:started_at] = started_at || now
      attributes[:published_at] = published_at || now
      attributes[:score_due_7d_at] = score_due_7d_at || attributes[:published_at] + 7.days
      attributes[:score_due_30d_at] = score_due_30d_at || attributes[:published_at] + 30.days
      attributes[:score_due_90d_at] = score_due_90d_at || attributes[:published_at] + 90.days
    end

    attributes
  end
end
