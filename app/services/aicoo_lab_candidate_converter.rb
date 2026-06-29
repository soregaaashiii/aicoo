class AicooLabCandidateConverter
  Result = Data.define(:experiments)

  CONVERTIBLE_STATUSES = %w[proposed approved].freeze
  LANDING_PAGE_SOURCE = "candidate_conversion"

  def initialize(candidates)
    @candidates = Array(candidates)
  end

  def call
    experiments = candidates.filter_map { |candidate| convert(candidate) }
    Result.new(experiments:)
  end

  private

  attr_reader :candidates

  def convert(candidate)
    return candidate.converted_experiment if candidate.status == "converted" && candidate.converted_experiment
    return unless CONVERTIBLE_STATUSES.include?(candidate.status)

    candidate.transaction do
      experiment = candidate.convert_to_experiment!
      experiment.mark_status!("preview_ready")
      create_landing_page!(candidate, experiment)
      create_profit_prediction!(candidate, experiment)
      experiment
    end
  end

  def create_landing_page!(candidate, experiment)
    landing_page = experiment.aicoo_lab_landing_page || AicooLabLandingPage.build_from_experiment(experiment)
    landing_page.generation_source = LANDING_PAGE_SOURCE
    landing_page.business ||= candidate.business || candidate.ensure_business!
    landing_page.status = "preview_ready"
    landing_page.save!
  end

  def create_profit_prediction!(candidate, experiment)
    experiment.aicoo_lab_predictions.find_or_create_by!(prediction_type: "profit", target_days: 90) do |prediction|
      prediction.predicted_value = candidate.expected_90d_profit_yen.to_d
      prediction.predicted_value_unit = "yen"
      prediction.confidence = candidate.success_probability
      prediction.rationale = candidate.rationale
    end
  end
end
