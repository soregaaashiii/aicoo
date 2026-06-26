class OpportunityDiscoveryItem < ApplicationRecord
  SOURCE_TYPES = %w[
    owner_discovery
    learning_report
    gsc
    ga4
    serp
    trend
    google_trends
    clarity
    reddit
    youtube
    x
    google_business_profile
  ].freeze
  STATUSES = %w[new pending approved reviewed converted rejected].freeze

  belongs_to :business, optional: true
  belongs_to :action_candidate, optional: true
  belongs_to :source_observation, class_name: "ExploreObservation", optional: true
  has_many :explore_observations, dependent: :nullify

  before_validation :set_defaults

  validates :title, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :opportunity_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :long_term_profit_score, :learning_value_score, :automation_value_score, :exploration_value_score, :strategic_score,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :decision_log_coefficient, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :practicality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :business_playbook_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :recent, -> { order(discovered_at: :desc, created_at: :desc) }
  scope :top_ranked, -> { order(Arel.sql("expected_value_yen DESC NULLS LAST, opportunity_score DESC NULLS LAST, discovered_at DESC NULLS LAST, created_at DESC")) }
  scope :pending_review, -> { where(status: %w[new pending approved]) }

  def convert_to_action_candidate!
    Aicoo::OpportunityActionCandidateConverter.new(self).call
  end

  def new_service_candidate?
    business_id.blank?
  end

  def execution_count
    action_candidate&.action_execution ? 1 : 0
  end

  def result_count
    action_candidate&.action_result ? 1 : 0
  end

  def success_count
    result = action_candidate&.action_result
    result&.actual_profit_yen.to_i.positive? ? 1 : 0
  end

  def failure_count
    result = action_candidate&.action_result
    result && result.actual_profit_yen.to_i <= 0 ? 1 : 0
  end

  private

  def set_defaults
    self.source_type = "owner_discovery" if source_type.blank?
    self.status = "new" if status.blank?
    self.opportunity_score = 50 if opportunity_score.nil?
    self.summary = description if summary.blank? && description.present?
    self.opportunity_type = "opportunity_validation" if opportunity_type.blank?
    self.market_signal_score = opportunity_score if market_signal_score.nil?
    self.urgency_score = 50 if urgency_score.nil?
    self.monetization_score = 50 if monetization_score.nil?
    self.feasibility_score = 50 if feasibility_score.nil?
    self.competition_score = 30 if competition_score.nil?
    self.expected_value_yen = conservative_value_yen if expected_value_yen.nil?
    self.confidence = opportunity_score if confidence.nil?
    self.discovered_at ||= Time.current
    apply_strategic_learning_defaults
    apply_evidence_defaults
    apply_practicality_defaults
    apply_business_playbook_defaults
  end

  def conservative_value_yen
    [ opportunity_score.to_i * 100, 1_000 ].max
  end

  def execution_prompt
    <<~TEXT
      Opportunityを検証してください。

      タイトル:
      #{title}

      内容:
      #{description.presence || "-"}

      完了条件:
      - 仮説が検証可能な小さい実行単位に落ちている
      - 実行後にActionResultへ結果を登録できる
    TEXT
  end

  def apply_strategic_learning_defaults
    result = Aicoo::StrategicLearningScorer.new(self, base_score: opportunity_score.presence || 50).call
    self.long_term_profit_score = result.components.fetch(:long_term_profit)
    self.learning_value_score = result.components.fetch(:learning)
    self.automation_value_score = result.components.fetch(:automation)
    self.exploration_value_score = result.components.fetch(:exploration)
    self.strategic_score = result.strategic_score
    self.decision_log_coefficient = result.decision_log_coefficient
    self.strategic_adjusted_score = result.final_score
    self.metadata = metadata.to_h.merge(
      "strategic_learning" => {
        "base_score" => result.base_score.to_s,
        "strategic_score" => result.strategic_score.to_s,
        "decision_log_coefficient" => result.decision_log_coefficient.to_s,
        "final_score" => result.final_score.to_s,
        "components" => result.components.transform_values(&:to_s),
        "decision_log_samples" => result.decision_log_samples,
        "decision_dimension_coefficients" => result.decision_dimension_coefficients
      }
    ).merge("strategic_learning_guardrail" => result.guardrail)
  end

  def apply_evidence_defaults
    result = Aicoo::EvidenceBuilder.new(self).call
    self.metadata = metadata.to_h.merge("evidence" => result.metadata)
  end

  def apply_practicality_defaults
    result = Aicoo::PracticalityScorer.new(self).call
    self.practicality_score = result.practicality_score
    self.practicality_warning = result.practicality_warning
    self.practicality_reason = result.practicality_reason
    self.metadata = metadata.to_h.merge("practicality" => result.metadata)
  end

  def apply_business_playbook_defaults
    result = Aicoo::BusinessPlaybookScorer.new(self).call
    self.business_playbook_score = result.score
    self.strategic_adjusted_score = (strategic_adjusted_score.to_d * result.coefficient).round(2)
    self.metadata = metadata.to_h.merge(
      "business_playbook" => result.metadata.merge(
        "score_after_playbook" => strategic_adjusted_score.to_s
      )
    )
  end
end
