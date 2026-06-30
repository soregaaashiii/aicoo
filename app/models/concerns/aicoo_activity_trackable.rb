module AicooActivityTrackable
  extend ActiveSupport::Concern

  included do
    after_commit :record_aicoo_activity_created, on: :create
    after_commit :record_aicoo_activity_updated, on: :update
    after_commit :record_aicoo_activity_destroyed, on: :destroy
  end

  private

  def record_aicoo_activity_created
    record_aicoo_activity(:create)
  end

  def record_aicoo_activity_updated
    record_aicoo_activity(:update)
  end

  def record_aicoo_activity_destroyed
    record_aicoo_activity(:destroy)
  end

  def record_aicoo_activity(action)
    Aicoo::ActivityIngestor.call(record: self, action:)
  end
end
