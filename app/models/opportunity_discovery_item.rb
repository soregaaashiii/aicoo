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
  STATUSES = %w[new reviewed converted rejected].freeze

  belongs_to :business, optional: true
  belongs_to :action_candidate, optional: true
  has_many :explore_observations, dependent: :nullify

  before_validation :set_defaults

  validates :title, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :opportunity_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :recent, -> { order(discovered_at: :desc, created_at: :desc) }
  scope :top_ranked, -> { order(Arel.sql("opportunity_score DESC NULLS LAST, discovered_at DESC NULLS LAST, created_at DESC")) }

  def convert_to_action_candidate!
    return action_candidate if action_candidate

    candidate = ActionCandidate.create!(
      business: business || Business.order(:name).first,
      title: title,
      description: description,
      action_type: "opportunity_validation",
      generation_source: "opportunity_discovery",
      department: "lab",
      status: "idea",
      immediate_value_yen: conservative_value_yen,
      success_probability: 0.3,
      expected_hours: 1,
      confidence_score: opportunity_score.to_i,
      data_confidence_score: 30,
      evaluation_reason: "Opportunity Discoveryから生成: #{source_type}",
      execution_prompt: execution_prompt,
      metadata: { "opportunity_id" => id, "opportunity_source_type" => source_type }.merge(metadata.to_h)
    )
    update!(action_candidate: candidate, status: "converted")
    candidate
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
    self.discovered_at ||= Time.current
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
end
