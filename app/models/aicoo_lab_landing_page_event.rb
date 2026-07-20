class AicooLabLandingPageEvent < ApplicationRecord
  EVENT_TYPES = %w[view cta_click signup scroll].freeze

  belongs_to :aicoo_lab_landing_page

  before_validation :set_defaults
  after_commit :refresh_lovable_learning, on: :create, if: :learning_signal?

  validates :event_type, inclusion: { in: EVENT_TYPES }

  private

  def learning_signal?
    event_type.in?(%w[cta_click signup scroll])
  end

  def refresh_lovable_learning
    Aicoo::Lovable::LearningRefresher.call(aicoo_lab_landing_page)
  end

  def set_defaults
    self.occurred_at = Time.current if occurred_at.blank?
    self.metadata = {} if metadata.blank?
  end
end
