require "digest"

class BusinessActivityLog < ApplicationRecord
  SOURCE_METHODS = %w[logger db_diff].freeze
  EVALUATION_STATUSES = %w[pending evaluating evaluated skipped].freeze

  belongs_to :business
  has_many :activity_evaluations, dependent: :destroy

  enum :source_method, {
    logger: "logger",
    db_diff: "db_diff"
  }, prefix: :source_method, validate: true

  enum :evaluation_status, {
    pending: "pending",
    evaluating: "evaluating",
    evaluated: "evaluated",
    skipped: "skipped"
  }, prefix: :evaluation, validate: true

  validates :source_app, :activity_type, :resource_type, :resource_id, :title,
            :occurred_at, :detected_at, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: { scope: :business_id }
  validates :estimated_work_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
  scope :evaluation_due, -> { where(evaluation_status: %w[pending evaluating]) }

  after_create :register_activity_evaluation_trigger
  after_create_commit :invoke_activity_evaluation_trigger

  def self.record!(business:, attributes:)
    normalized = normalize_attributes(attributes)
    find_or_initialize_by(business:, idempotency_key: normalized.fetch(:idempotency_key)).tap do |activity_log|
      created = activity_log.new_record?
      activity_log.assign_attributes(normalized) if created
      activity_log.save!
      Rails.logger.info(
        "[BusinessActivityLog] #{created ? 'created' : 'deduplicated'} " \
        "id=#{activity_log.id} business=#{business.name} activity_type=#{activity_log.activity_type} " \
        "resource=#{activity_log.resource_type}##{activity_log.resource_id}"
      )
    end
  end

  def self.normalize_attributes(attributes)
    now = Time.current
    attrs = attributes.to_h.symbolize_keys
    source_app = attrs[:source_app].presence || "unknown"
    activity_type = attrs[:activity_type].presence || "activity_logged"
    resource_type = attrs[:resource_type].presence || "unknown"
    resource_id = attrs[:resource_id].presence || "unknown"
    occurred_at = parse_time(attrs[:occurred_at]) || now

    {
      source_app:,
      activity_type:,
      resource_type:,
      resource_id: resource_id.to_s,
      title: attrs[:title].presence || activity_type.to_s.humanize,
      occurred_at:,
      detected_at: parse_time(attrs[:detected_at]) || now,
      changed_fields: attrs[:changed_fields].presence || {},
      before_snapshot: attrs[:before_snapshot].presence || {},
      after_snapshot: attrs[:after_snapshot].presence || {},
      diff_summary: attrs[:diff_summary],
      metadata: attrs[:metadata].presence || {},
      estimated_work_seconds: attrs[:estimated_work_seconds],
      source_method: attrs[:source_method].presence || "logger",
      idempotency_key: attrs[:idempotency_key].presence || build_idempotency_key(source_app, activity_type, resource_type, resource_id, occurred_at),
      evaluation_status: attrs[:evaluation_status].presence || "pending"
    }
  end

  def self.parse_time(value)
    return value if value.respond_to?(:in_time_zone)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def self.build_idempotency_key(source_app, activity_type, resource_type, resource_id, occurred_at)
    Digest::SHA256.hexdigest([ source_app, activity_type, resource_type, resource_id, occurred_at.to_i ].join(":"))
  end

  private

  def register_activity_evaluation_trigger
    write_activity_evaluation_trigger_chain(
      "record_created" => true,
      "after_create_called" => true,
      "after_commit_called" => false,
      "after_commit_skipped" => false,
      "trigger_registered" => true,
      "trigger_called" => false,
      "trigger_completed" => false,
      "builder_called" => false,
      "builder_completed" => false,
      "registered_at" => Time.current.iso8601,
      "return_point" => "after_create"
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[ActivityEvaluationTrigger] registration metadata save failed " \
      "activity_log_id=#{id} error=#{e.class}: #{e.message}"
    )
  end

  def invoke_activity_evaluation_trigger
    write_activity_evaluation_trigger_chain(
      "after_commit_called" => true,
      "trigger_registered" => true,
      "trigger_called" => true,
      "invoked_by" => "after_create_commit",
      "called_at" => Time.current.iso8601,
      "return_point" => "trigger_called",
      "exception" => nil,
      "skip_reason" => nil
    )
    Rails.logger.info(
      "[ActivityEvaluationTrigger] after_create_commit start " \
      "activity_log_id=#{id} business_id=#{business_id} activity_type=#{activity_type}"
    )

    result = Aicoo::ActivityEvaluationTrigger.call(
      business:,
      invoked_by: "after_create_commit",
      trigger_event_id: id
    )
    reload
    completed = result.present? && result.exception.blank? && result.builder_failed_count.to_i.zero?
    write_activity_evaluation_trigger_chain(
      "trigger_completed" => result.present?,
      "builder_called" => result&.builder_invoked_count.to_i.positive?,
      "builder_completed" => completed,
      "completed_at" => Time.current.iso8601,
      "return_point" => completed ? "completed" : "builder_incomplete",
      "exception" => result&.exception,
      "skip_reason" => completed ? nil : result&.exception.presence || "builder_incomplete"
    )
    Rails.logger.info(
      "[ActivityEvaluationTrigger] after_create_commit finish " \
      "activity_log_id=#{id} builder_invoked=#{result&.builder_invoked_count.to_i} " \
      "builder_completed=#{result&.builder_completed_count.to_i} " \
      "builder_failed=#{result&.builder_failed_count.to_i}"
    )
  rescue StandardError => e
    reload
    write_activity_evaluation_trigger_chain(
      "trigger_completed" => false,
      "builder_completed" => false,
      "completed_at" => Time.current.iso8601,
      "return_point" => "trigger_exception",
      "exception" => "#{e.class}: #{e.message}",
      "skip_reason" => "trigger_exception"
    )
    Rails.logger.error(
      "[ActivityEvaluationTrigger] after_create_commit failed " \
      "activity_log_id=#{id} error=#{e.class}: #{e.message}"
    )
  end

  def write_activity_evaluation_trigger_chain(attributes)
    current_metadata = metadata.to_h
    chain = current_metadata["activity_evaluation_trigger_chain"].to_h.merge(attributes)
    update_columns(
      metadata: current_metadata.merge("activity_evaluation_trigger_chain" => chain),
      updated_at: Time.current
    )
  end
end
