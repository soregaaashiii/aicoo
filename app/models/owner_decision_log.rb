class OwnerDecisionLog < ApplicationRecord
  DECISION_TYPES = %w[approve reject convert complete skip copied executed].freeze
  DECISION_SOURCES = %w[
    owner_focus
    owner_tasks
    opportunity_detail
    action_candidate_detail
    codex_prompt_detail
    daily_run
  ].freeze
  POSITIVE_DECISIONS = %w[approve convert complete copied executed].freeze
  EXECUTION_DECISIONS = %w[complete copied executed].freeze

  belongs_to :business, optional: true
  belongs_to :queue_item, class_name: "OwnerExecutionQueueItem", optional: true

  validates :subject_type, :subject_id, :decision_type, :decision_source, :decided_at, presence: true
  validates :decision_type, inclusion: { in: DECISION_TYPES }
  validates :decision_source, inclusion: { in: DECISION_SOURCES }

  scope :recent, -> { order(decided_at: :desc, created_at: :desc) }
  scope :today, -> { where(decided_at: Time.current.all_day) }
  scope :last_7_days, -> { where(decided_at: 7.days.ago..) }
  scope :last_30_days, -> { where(decided_at: 30.days.ago..) }

  def self.record!(subject:, decision_type:, decision_source:, queue_item: nil, previous_status: nil, new_status: nil, reason: nil, metadata: {})
    snapshot = Snapshot.new(subject, queue_item:).to_h
    decided_at = Time.current
    duplicate = recent_duplicate(
      subject:,
      decision_type:,
      decision_source:,
      previous_status:,
      new_status:,
      queue_item:
    )
    return duplicate if duplicate

    create!(
      snapshot.merge(
        decision_type:,
        decision_source:,
        previous_status:,
        new_status:,
        reason: reason.presence,
        decided_at:,
        metadata: snapshot.fetch(:metadata).merge(metadata.to_h.stringify_keys)
      )
    )
  end

  def self.recent_duplicate(subject:, decision_type:, decision_source:, previous_status:, new_status:, queue_item:)
    where(
      subject_type: subject.class.name,
      subject_id: subject.id,
      decision_type:,
      decision_source:,
      previous_status:,
      new_status:
    ).where(decided_at: 2.seconds.ago..).then do |scope|
      queue_item ? scope.where(queue_item:) : scope
    end.first
  end

  class Snapshot
    attr_reader :subject, :queue_item

    def initialize(subject, queue_item: nil)
      @subject = subject
      @queue_item = queue_item
    end

    def to_h
      {
        subject_type: subject.class.name,
        subject_id: subject.id,
        queue_item:,
        business: business_record,
        title: snapshot_title,
        expected_value_yen: expected_value_yen,
        confidence: confidence,
        risk_level: risk_level,
        action_type: action_type,
        opportunity_type: opportunity_type,
        generation_source: generation_source,
        metadata: metadata
      }
    end

    private

    def business_record
      return subject.business if subject.respond_to?(:business)

      nil
    end

    def snapshot_title
      return subject.title if subject.respond_to?(:title)

      "#{subject.class.name} ##{subject.id}"
    end

    def expected_value_yen
      first_existing(:expected_value_yen, :expected_total_value_yen, :final_expected_value_yen, :expected_profit_yen)
    end

    def confidence
      first_existing(:confidence, :confidence_score, :final_confidence_score)
    end

    def risk_level
      return subject.risk_level if subject.respond_to?(:risk_level) && subject.risk_level.present?
      return queue_item.risk_level if queue_item&.risk_level.present?
      return "high" if subject.is_a?(ActionPredictionCalibration) && subject.warning_level == "danger"
      return "medium" if subject.is_a?(ActionPredictionCalibration)

      nil
    end

    def action_type
      return subject.action_type if subject.respond_to?(:action_type) && subject.action_type.present?
      return subject.action_candidate&.action_type if subject.respond_to?(:action_candidate) && subject.action_candidate
      return subject.metadata.to_h["action_type"] if subject.respond_to?(:metadata)

      nil
    end

    def opportunity_type
      return subject.opportunity_type if subject.respond_to?(:opportunity_type) && subject.opportunity_type.present?
      return subject.metadata.to_h["opportunity_type"] if subject.respond_to?(:metadata)

      nil
    end

    def generation_source
      return subject.generation_source if subject.respond_to?(:generation_source) && subject.generation_source.present?
      return subject.action_candidate&.generation_source if subject.respond_to?(:action_candidate) && subject.action_candidate
      return subject.source_type if subject.respond_to?(:source_type) && subject.source_type.present?
      return subject.metadata.to_h["generation_source"] if subject.respond_to?(:metadata)

      nil
    end

    def metadata
      data = { "subject_model" => subject.class.name }
      data["item_type"] = subject.item_type if subject.respond_to?(:item_type)
      data["generated_from"] = subject.generated_from if subject.respond_to?(:generated_from)
      data["strategic_learning"] = subject.metadata.to_h["strategic_learning"] if subject.respond_to?(:metadata) && subject.metadata.to_h["strategic_learning"].present?
      data["practicality"] = subject.metadata.to_h["practicality"] if subject.respond_to?(:metadata) && subject.metadata.to_h["practicality"].present?
      data["evidence"] = subject.metadata.to_h["evidence"] if subject.respond_to?(:metadata) && subject.metadata.to_h["evidence"].present?
      data["action_expansion"] = subject.metadata.to_h["action_expansion"] if subject.respond_to?(:metadata) && subject.metadata.to_h["action_expansion"].present?
      data["action_expansion_tasks"] = action_expansion_tasks if action_expansion_tasks.any?
      data
    end

    def action_expansion_tasks
      expansion = subject.metadata.to_h["action_expansion"].to_h if subject.respond_to?(:metadata)
      Array(expansion&.fetch("recommended_tasks", []))
    end

    def first_existing(*attributes)
      attributes.each do |attribute|
        next unless subject.respond_to?(attribute)

        value = subject.public_send(attribute)
        return value if value.present?
      end

      nil
    end
  end
end
