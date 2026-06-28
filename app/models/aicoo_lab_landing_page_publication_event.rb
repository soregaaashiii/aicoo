class AicooLabLandingPagePublicationEvent < ApplicationRecord
  EVENT_TYPES = %w[pause resume archive publish schedule].freeze

  belongs_to :aicoo_lab_landing_page

  before_validation :set_defaults

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.metadata ||= {}
  end
end
