class BusinessPlaybook < ApplicationRecord
  belongs_to :business

  validates :sample_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def action_type_rows
    action_type_summary.to_h.values.sort_by { |row| -row.to_h["score"].to_d }
  end

  def opportunity_type_rows
    opportunity_type_summary.to_h.values.sort_by { |row| -row.to_h["score"].to_d }
  end

  def task_rows
    metadata.to_h.fetch("task_summary", {}).values.sort_by { |row| -row.to_h["score"].to_d }
  end

  def analysis_rows
    metadata.to_h.fetch("analysis_summary", {}).values.sort_by { |row| -row.to_h["score"].to_d }
  end

  def learned?
    sample_count.positive?
  end
end
