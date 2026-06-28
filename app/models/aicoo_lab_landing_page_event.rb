class AicooLabLandingPageEvent < ApplicationRecord
  EVENT_TYPES = %w[view cta_click signup scroll].freeze

  belongs_to :aicoo_lab_landing_page

  before_validation :set_defaults

  validates :event_type, inclusion: { in: EVENT_TYPES }

  private

  def set_defaults
    self.occurred_at = Time.current if occurred_at.blank?
    self.metadata = {} if metadata.blank?
  end
end
