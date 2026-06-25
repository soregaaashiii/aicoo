module Aicoo
  class DecisionLogCoefficient
    MIN_SAMPLE_SIZE = 3
    MIN_COEFFICIENT = 0.75.to_d
    MAX_COEFFICIENT = 1.25.to_d

    Result = Data.define(:coefficient, :samples, :dimension_coefficients)

    def initialize(subject)
      @subject = subject
    end

    def call
      coefficients = dimensions.filter_map { |dimension, value| coefficient_for(dimension, value) if value.present? }
      return Result.new(coefficient: 1.to_d, samples: 0, dimension_coefficients: {}) if coefficients.empty?

      coefficient = (coefficients.sum { |item| item.fetch(:coefficient) } / coefficients.size).round(3)
      Result.new(
        coefficient: clamp(coefficient),
        samples: coefficients.sum { |item| item.fetch(:samples) },
        dimension_coefficients: coefficients.to_h { |item| [ item.fetch(:dimension), item.except(:dimension) ] }
      )
    end

    private

    attr_reader :subject

    def dimensions
      {
        action_type: value_for(:action_type),
        opportunity_type: value_for(:opportunity_type),
        risk_level: value_for(:risk_level),
        generation_source: value_for(:generation_source)
      }
    end

    def value_for(attribute)
      return subject.public_send(attribute) if subject.respond_to?(attribute) && subject.public_send(attribute).present?
      return subject.action_candidate.public_send(attribute) if subject.respond_to?(:action_candidate) && subject.action_candidate&.respond_to?(attribute)
      return subject.metadata.to_h[attribute.to_s] if subject.respond_to?(:metadata)

      nil
    end

    def coefficient_for(dimension, value)
      scope = OwnerDecisionLog.last_30_days.where(dimension => value)
      samples = scope.count
      return if samples < MIN_SAMPLE_SIZE

      positive_count = scope.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count
      negative_count = scope.where(decision_type: %w[reject skip]).count
      positive_rate = positive_count.to_d / samples.to_d
      negative_rate = negative_count.to_d / samples.to_d
      coefficient = 1.to_d + ((positive_rate - negative_rate) * 0.25.to_d)

      {
        dimension:,
        value:,
        samples:,
        positive_rate: positive_rate.round(3),
        negative_rate: negative_rate.round(3),
        coefficient: clamp(coefficient.round(3))
      }
    end

    def clamp(value)
      [ [ value.to_d, MIN_COEFFICIENT ].max, MAX_COEFFICIENT ].min
    end
  end
end
