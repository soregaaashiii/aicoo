class AutoBuildTask < ApplicationRecord
  STATUSES = %w[pending building completed failed cancelled].freeze
  BUILD_STRATEGIES = %w[priority_a priority_b priority_c].freeze
  RISK_LEVELS = %w[low medium high].freeze
  ACTIVE_STATUSES = %w[pending building].freeze

  belongs_to :business
  belongs_to :aicoo_daily_run, optional: true
  belongs_to :auto_revision_task, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :build_strategy, inclusion: { in: BUILD_STRATEGIES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }
  validates :priority_score, :expected_value_yen, :learning_value_score,
            :estimated_cost_yen, :estimated_build_hours,
            numericality: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :pending, -> { where(status: "pending") }
  scope :building, -> { where(status: "building") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :by_priority, -> { order(priority_score: :desc, created_at: :desc) }

  def build_strategy_label
    {
      "priority_a" => "Priority A: 期待利益が高い",
      "priority_b" => "Priority B: リソース余裕でBuild",
      "priority_c" => "Priority C: Learning Value優先"
    }.fetch(build_strategy, build_strategy)
  end

  def approval_required?
    business.auto_build_requires_approval?
  end
end
