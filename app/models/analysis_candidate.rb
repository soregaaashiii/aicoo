class AnalysisCandidate < ApplicationRecord
  SOURCES = %w[
    gsc
    ga4
    serp
    x
    youtube
    clarity
    google_ads
    meta_ads
    reddit
    github
    product_hunt
    explore
  ].freeze
  EXECUTION_MODES = DataSourceCostProfile::EXECUTION_MODES
  STATUSES = %w[pending running completed skipped failed].freeze

  belongs_to :business

  validates :analysis_source, presence: true
  validates :execution_mode, inclusion: { in: EXECUTION_MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :due_on, presence: true
  validates :analysis_source, uniqueness: { scope: %i[business_id due_on] }
  validates :expected_value_yen, :estimated_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :estimated_cost_yen, :confidence, :priority, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :for_today, -> { where(due_on: Date.current) }
  scope :ordered, -> { order(priority: :desc, expected_value_yen: :desc, created_at: :desc) }

  def auto? = execution_mode == "auto"
  def smart? = execution_mode == "smart"
  def manual? = execution_mode == "manual"

  def display_name
    DataSourceCostProfile.for_source(analysis_source).name
  end

  def roi_label
    return "無料/未計算" if roi.blank?

    roi.to_d.round(1).to_s
  end
end
