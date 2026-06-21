class AicooLabAiCandidatePayloadImporter
  Result = Data.define(:created_candidates, :skipped_titles)

  PERMITTED_ATTRIBUTES = %w[
    title description experiment_type market_category acquisition_channel
    expected_90d_profit_yen success_probability budget_yen
    estimated_work_minutes assumed_price_yen rationale
    neglect_loss_90d_yen neglect_loss_reason
    target_user problem_statement hypothesis validation_method
    expected_learning rejection_condition
  ].freeze

  def initialize(payload:)
    @payload = payload
  end

  def call
    created_candidates = []
    skipped_titles = []

    candidate_payloads.each do |candidate_payload|
      attributes = normalized_attributes(candidate_payload)
      title = attributes.fetch("title")

      if duplicate_title?(title)
        skipped_titles << title
        next
      end

      created_candidates << AicooLabExperimentCandidate.create!(
        attributes.merge(status: "proposed", generation_source: "ai_paste")
      )
    end

    Result.new(created_candidates:, skipped_titles:)
  end

  private

  attr_reader :payload

  def candidate_payloads
    candidates = payload.is_a?(Array) ? payload : payload.fetch("candidates")
    raise ArgumentError, "JSON must include candidates array" unless candidates.is_a?(Array)

    candidates
  end

  def normalized_attributes(candidate_payload)
    attributes = candidate_payload.to_h.slice(*PERMITTED_ATTRIBUTES)
    attributes["title"] = attributes["title"].to_s.strip
    raise ArgumentError, "Candidate title is required" if attributes["title"].blank?

    attributes
  end

  def duplicate_title?(title)
    AicooLabExperimentCandidate.where(title:).exists?
  end
end
