class ActionCandidate < ApplicationRecord
  attr_reader :business_promotion_result

  ACTION_TYPES = %w[
    seo_article
    seo_improvement
    new_article_candidate
    smoking_info_verify
    shop_phone_verify
    shop_data_cleanup
    article_create
    article_update
    serp_research
    market_research
    new_business
    lp_experiment
    market_test
    build_lp
    build_mvp
    ui_improvement
    feature_development
    sales
    outsourcing
    automation
    pivot
    withdraw
    sell
    data_preparation
    evaluation_tuning
    learning_improvement
    opportunity_validation
    other
  ].freeze

  STATUSES = %w[idea proposal planning pending valuation_review_required approved executor_queued in_progress done rejected archived].freeze
  INACTIVE_STATUSES = %w[archived rejected done canceled cancelled invalid].freeze
  GENERATION_SOURCES = %w[manual seed ai_business ai_cross_business ai_reevaluation ai_insight learning_report opportunity_discovery business_analyzer suelog_db serp traffic_channel integrated_decision].freeze
  DEPARTMENTS = %w[general revenue lab new_business].freeze

  belongs_to :business, optional: true
  has_one :action_result, dependent: :destroy
  has_one :action_execution, dependent: :destroy
  has_many :action_execution_logs, dependent: :destroy
  has_many :revenue_events, dependent: :nullify
  has_many :action_candidate_score_snapshots, dependent: :destroy
  has_many :auto_revision_tasks, dependent: :destroy
  has_many :codex_prompt_drafts, dependent: :destroy
  has_many :opportunity_discovery_items, dependent: :nullify

  def department=(value)
    @department_explicitly_assigned = true if value.present?
    super
  end

  before_validation :set_defaults
  before_validation :sanitize_owned_target_urls
  before_save :apply_execution_feasibility_correction
  before_save :calculate_scores
  after_commit :sync_serp_query_counters, on: %i[create update]
  after_commit :auto_publish_new_business_candidate, on: %i[create update]
  after_commit :run_auto_revision_autopilot, on: %i[create update]

  validates :title, presence: true
  validates :action_type, inclusion: { in: ACTION_TYPES }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :generation_source, inclusion: { in: GENERATION_SOURCES }, allow_blank: true
  validates :department, inclusion: { in: DEPARTMENTS }, allow_blank: true
  validates :success_probability, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validates :strategic_value_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :risk_reduction_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :data_confidence_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :priority_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :expected_hours, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :immediate_value_yen, numericality: { only_integer: true }, allow_nil: true
  validates :neglect_loss_90d_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :estimated_neglect_loss_90d_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expected_revenue_value_yen, :expected_learning_value_yen, :expected_total_value_yen,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :final_expected_value_yen, :final_confidence_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :practicality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :business_playbook_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :by_expected_value, -> { includes(:business).order(Arel.sql("expected_hourly_value_yen DESC NULLS LAST, expected_profit_yen DESC NULLS LAST")) }
  scope :by_recommendation, -> { includes(:business).order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST")) }
  scope :active_for_ranking, -> { where.not(status: INACTIVE_STATUSES) }
  scope :approved_queue, -> { where(status: "approved").order(approved_at: :desc, expected_total_value_yen: :desc) }
  scope :for_department, ->(department) { department == "general" ? all : where(department:) }

  def data_preparation?
    action_type == "data_preparation"
  end

  def execution_mode
    metadata.to_h["execution_mode"].presence || "code_revision"
  end

  def code_revision_execution_mode?
    execution_mode == "code_revision"
  end

  def unfinished_executor_task
    return unless data_preparation? || generation_source == "ai_insight"

    AicooExecutorTask.unfinished_for_action_candidate(self)
  end

  def approve!(approved_by: nil)
    transaction do
      @business_promotion_result = Aicoo::ActionCandidateBusinessPromoter.new(self).call
      update!(status: "approved", approved_at: Time.current, approved_by:)
      ensure_action_execution!
      AicooExecutor::TaskBuilder.from_action_candidate(self)
      task = AutoRevisionTask.from_action_candidate(self, generated_by: "action_candidate_approval")
      task&.approve! if task&.status&.in?(%w[draft waiting_approval])
      task
    end
  end

  def mark_executor_queued!
    update!(status: "executor_queued", executor_queued_at: Time.current)
  end

  def ensure_action_execution!
    action_execution || create_action_execution!(
      status: "ready",
      execution_type: "manual",
      execution_prompt: Aicoo::ExecutionPromptBuilder.new(self).call
    )
  end

  def executed?
    status == "done" || action_result.present? || action_execution&.status == "completed"
  end

  def mark_executed!(executed_by: "owner", executed_at: Time.current)
    transaction do
      execution = ensure_action_execution!
      execution.complete!(
        result_summary: "施策詳細から実行済みにしました。"
      ) unless execution.status == "completed"

      create_action_result!(
        action_execution: execution,
        business: business,
        executed_on: executed_at.to_date,
        evaluated_on: executed_at.to_date,
        evaluation_status: "pending",
        note: "施策詳細から実行済みにしました。詳細評価は未入力です。",
        metadata: {
          "marked_executed_from" => "action_candidate_detail",
          "executed_by" => executed_by,
          "executed_at" => executed_at.iso8601
        }
      ) unless action_result

      update!(
        status: "done",
        metadata: metadata.to_h.merge(
          "executed" => true,
          "executed_at" => executed_at.iso8601,
          "executed_by" => executed_by,
          "execution_record_source" => "action_candidate_detail"
        )
      )
    end
  end

  def revenue_ratio
    value_ratio(expected_revenue_value_yen)
  end

  def learning_ratio
    return 0 if expected_total_value_yen.to_i.zero?

    100 - revenue_ratio
  end

  def calibrated_success_probability
    apply_probability_calibration(success_probability.to_d, prediction_calibration)
  end

  private

  def set_defaults
    self.action_type = "other" if action_type.blank?
    self.status = "idea" if status.blank?
    self.generation_source = "manual" if generation_source.blank?
    self.department = auto_classified_department if auto_classify_department?
    self.success_probability = 0 if success_probability.nil?
    self.immediate_value_yen = 0 if immediate_value_yen.nil?
    self.strategic_value_score = 0 if strategic_value_score.nil?
    self.risk_reduction_score = 0 if risk_reduction_score.nil?
    self.confidence_score = 0 if confidence_score.nil?
    self.data_confidence_score = 20 if data_confidence_score.nil?
    self.priority_score = 0 if priority_score.nil?
    self.neglect_loss_90d_yen = 0 if neglect_loss_90d_yen.nil?
    self.estimated_neglect_loss_90d_yen = 0 if estimated_neglect_loss_90d_yen.nil?
    self.expected_revenue_value_yen = 0 if expected_revenue_value_yen.nil?
    self.expected_learning_value_yen = 0 if expected_learning_value_yen.nil?
    self.expected_total_value_yen = 0 if expected_total_value_yen.nil?
    self.final_expected_value_yen = 0 if final_expected_value_yen.nil?
    self.final_confidence_score = 0 if final_confidence_score.nil?
  end

  def calculate_scores
    calibration = prediction_calibration
    raw_expected_profit_yen = immediate_value_yen.to_d * success_probability.to_d
    adjusted_success_probability = apply_probability_calibration(success_probability.to_d, calibration)
    adjusted_expected_profit_yen = raw_expected_profit_yen * calibration.profit_factor
    self.expected_profit_yen = adjusted_expected_profit_yen.round
    apply_prediction_calibration_metadata(
      calibration:,
      raw_expected_profit_yen:,
      adjusted_expected_profit_yen:,
      adjusted_success_probability:
    )
    self.expected_hourly_value_yen = calculate_expected_hourly_value
    self.roi = calculate_roi
    self.final_score = calculate_final_score
    self.expected_revenue_value_yen = calculate_expected_revenue_value
    self.expected_learning_value_yen = LearningValueCalculator.new(self).value_yen
    self.expected_total_value_yen = expected_revenue_value_yen.to_i + expected_learning_value_yen.to_i
    if business.blank?
      self.final_expected_value_yen = expected_total_value_yen.to_i
      self.final_confidence_score = confidence_score.to_i
      self.metadata = metadata.to_h.merge("business_pending_publication" => true)
      return
    end

    apply_meta_evaluation
    apply_evidence
    apply_action_expansion
    sanitize_owned_target_urls
    apply_strategic_learning
    apply_practicality_filter
    apply_business_playbook
    apply_business_type_playbook
    sanitize_owned_target_urls
  end

  def calculate_expected_hourly_value
    return nil if expected_hours.blank? || expected_hours.to_d.zero?

    (expected_profit_yen.to_d / expected_hours.to_d).round
  end

  def calculate_roi
    return nil if cost_yen.blank? || cost_yen.to_d.zero?

    expected_profit_yen.to_d / cost_yen.to_d
  end

  def calculate_final_score
    hourly_value = expected_hourly_value_yen || 0
    strategic_value = strategic_value_score.to_i * 100
    risk_reduction_value = risk_reduction_score.to_i * 100

    (hourly_value * 0.7) + (strategic_value * 0.2) + (risk_reduction_value * 0.1)
  end

  def calculate_expected_revenue_value
    [
      expected_profit_yen.to_i,
      neglect_loss_90d_yen.to_i,
      estimated_neglect_loss_90d_yen.to_i
    ].sum
  end

  def value_ratio(value)
    return 0 if expected_total_value_yen.to_i.zero?

    (value.to_d / expected_total_value_yen.to_d * 100).round
  end

  def auto_classify_department?
    new_record? && !department_explicitly_assigned? && (department.blank? || department == "general")
  end

  def department_explicitly_assigned?
    @department_explicitly_assigned == true
  end

  def auto_classified_department
    ActionCandidateDepartmentClassifierService.new.classify(self)
  end

  def apply_execution_feasibility_correction
    AicooExecutionFeasibilityCorrectionService.new(self).apply!
  end

  def sanitize_owned_target_urls
    return unless business

    self.metadata = Aicoo::ActionCandidateTargetSanitizer.call(business:, metadata:)
  end

  def apply_meta_evaluation
    result = AicooMetaEvaluator::MetaEvaluator.new(self).call
    self.final_expected_value_yen = result.final_expected_value_yen
    self.final_confidence_score = result.final_confidence_score
    self.metadata = metadata.to_h.merge("evaluator_breakdown" => result.evaluator_breakdown)
  end

  def apply_evidence
    result = Aicoo::EvidenceBuilder.new(self).call
    self.metadata = metadata.to_h.merge("evidence" => result.metadata)
  end

  def apply_action_expansion
    result = Aicoo::ActionExpansionEngine.new(self).call
    self.metadata = metadata.to_h.merge("action_expansion" => result.metadata)
  end

  def apply_strategic_learning
    result = Aicoo::StrategicLearningScorer.new(self, base_score: final_score).call
    self.final_score = result.final_score
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

  def apply_practicality_filter
    result = Aicoo::PracticalityScorer.new(self).call
    self.practicality_score = result.practicality_score
    self.practicality_warning = result.practicality_warning
    self.practicality_reason = result.practicality_reason
    self.final_score = (final_score.to_d * practicality_multiplier(result.practicality_score)).round(2)
    self.metadata = metadata.to_h.merge(
      "practicality" => result.metadata.merge(
        "score_before_practicality" => (metadata.to_h.dig("strategic_learning", "final_score") || final_score).to_s,
        "score_after_practicality" => final_score.to_s,
        "multiplier" => practicality_multiplier(result.practicality_score).to_s
      )
    )
  end

  def apply_business_playbook
    result = Aicoo::BusinessPlaybookScorer.new(self).call
    self.business_playbook_score = result.score
    self.final_score = (final_score.to_d * result.coefficient).round(2)
    self.metadata = metadata.to_h.merge(
      "business_playbook" => result.metadata.merge(
        "score_before_playbook" => (metadata.to_h.dig("practicality", "score_after_practicality") || final_score).to_s,
        "score_after_playbook" => final_score.to_s
      )
    )
  end

  def apply_business_type_playbook
    return unless business

    decision = business.business_type_playbook.call(
      title:,
      description:,
      action_type:,
      evaluation_reason:,
      execution_prompt:
    )
    coefficient = decision.preferred ? 1.08.to_d : 1.to_d
    self.final_score = (final_score.to_d * coefficient).round(2)
    self.metadata = metadata.to_h.merge(
      "business_type_playbook" => decision.metadata.merge(
        "score_before_business_type" => (metadata.to_h.dig("business_playbook", "score_after_playbook") || final_score).to_s,
        "score_after_business_type" => final_score.to_s,
        "coefficient" => coefficient.to_s
      )
    )
    return unless new_record?
    return if decision.reason.blank? || evaluation_reason.to_s.include?(decision.reason)

    self.evaluation_reason = [ evaluation_reason, decision.reason ].compact_blank.join("\n")
  end

  def practicality_multiplier(score)
    score = score.to_d
    return 0.85.to_d if score < 30
    return 0.92.to_d if score < 50
    return 1.0.to_d if score < 70

    1.12.to_d
  end

  def prediction_calibration
    ActionPredictionCalibration.for_action_type(action_type.presence || "other")
  end

  def apply_probability_calibration(raw_probability, calibration)
    adjusted = raw_probability.to_d * calibration.probability_factor
    return 0.01.to_d if adjusted < 0.01.to_d
    return 0.99.to_d if adjusted > 0.99.to_d

    adjusted
  end

  def apply_prediction_calibration_metadata(calibration:, raw_expected_profit_yen:, adjusted_expected_profit_yen:, adjusted_success_probability:)
    self.metadata = metadata.to_h.merge(
      "prediction_calibration" => {
        "action_type" => action_type,
        "sample_count" => calibration.sample_count.to_i,
        "active" => calibration.active?,
        "profit_calibration_factor" => calibration.profit_factor.to_s,
        "probability_calibration_factor" => calibration.probability_factor.to_s,
        "raw_expected_profit_yen" => raw_expected_profit_yen.round,
        "adjusted_expected_profit_yen" => adjusted_expected_profit_yen.round,
        "raw_success_probability" => success_probability.to_d.to_s,
        "adjusted_success_probability" => adjusted_success_probability.to_s,
        "last_calculated_at" => calibration.last_calculated_at&.iso8601
      }
    )
  end

  def sync_serp_query_counters
    return unless generation_source == "serp"
    return unless business

    source_query = metadata.to_h["source_query"].presence || metadata.to_h["serp_keyword"].presence
    return if source_query.blank?

    serp_query = business.serp_queries.find_by(normalized_query: SerpQuery.normalize(source_query))
    return unless serp_query

    counts = business.action_candidates.where(generation_source: "serp").where(
      "metadata ->> 'source_query' = ? OR metadata ->> 'serp_keyword' = ?",
      source_query,
      source_query
    )
    serp_query.update_columns(
      total_candidates_generated: counts.count,
      total_candidates_approved: counts.where(status: "approved").count,
      updated_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[SERP] ActionCandidate##{id} serp query counter sync failed: #{e.class} #{e.message}")
  end

  def run_auto_revision_autopilot
    Aicoo::AutoRevisionAutopilot.call(self, generated_by: "action_candidate_after_commit")
  rescue StandardError => e
    Rails.logger.warn("[ActionCandidate] auto revision autopilot failed candidate_id=#{id}: #{e.class}: #{e.message}")
  end

  def auto_publish_new_business_candidate
    return unless Aicoo::ActionCandidateBusinessPromoter.new_business_candidate?(self)
    return if status.in?(%w[rejected archived done])
    return if metadata.to_h.dig("auto_new_business_publication", "completed")
    return if metadata.to_h["do_not_recreate"] || metadata.to_h["auto_republish_blocked"]

    Aicoo::Serp::AutoNewBusinessPublisher.call(candidates: [ self ], source: "action_candidate_auto_publish")
  rescue StandardError => e
    Rails.logger.warn("[ActionCandidate] auto new business publish skipped action_candidate_id=#{id}: #{e.class}: #{e.message}")
  end
end
