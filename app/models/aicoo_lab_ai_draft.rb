class AicooLabAiDraft < ApplicationRecord
  STATUSES = %w[draft approved rejected imported].freeze

  belongs_to :generation_run, class_name: "AicooLabGenerationRun"

  before_validation :set_defaults

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def candidate_count
    candidates.size
  end

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end

  def reject!
    update!(status: "rejected")
  end

  def importable?
    status == "approved"
  end

  def mark_imported!
    update!(status: "imported", imported_at: Time.current)
  end

  private

  def candidates
    parsed_json.is_a?(Array) ? parsed_json : parsed_json.fetch("candidates", [])
  end

  def set_defaults
    self.status = "draft" if status.blank?
  end
end
