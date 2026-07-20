class AicooLabLandingPageEvent < ApplicationRecord
  EVENT_TYPES = %w[view cta_click signup scroll].freeze

  belongs_to :aicoo_lab_landing_page

  before_validation :set_defaults
  after_commit :refresh_lovable_learning, on: :create, if: :learning_signal?

  validates :event_type, inclusion: { in: EVENT_TYPES }

  private

  def learning_signal?
    return true if event_type.in?(%w[cta_click signup scroll])
    return false unless event_type == "view"

    view_count = aicoo_lab_landing_page.aicoo_lab_landing_page_events.where(event_type: "view").count
    view_count == Aicoo::Lovable::LandingPageLearningComparison::MIN_PAGEVIEWS || (view_count > 0 && (view_count % 50).zero?)
  end

  def refresh_lovable_learning
    Aicoo::Lovable::LearningRefresher.call(aicoo_lab_landing_page)
  end

  def set_defaults
    self.occurred_at = Time.current if occurred_at.blank?
    self.metadata = {} if metadata.blank?
  end
end
