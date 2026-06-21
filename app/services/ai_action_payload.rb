require "bigdecimal"

class AiActionPayload
  def self.normalize(attributes)
    new(attributes).normalize
  end

  def initialize(attributes)
    @attributes = attributes.to_h
  end

  def normalize
    {
      title: string_value("title"),
      description: string_value("description"),
      action_type: action_type,
      immediate_value_yen: integer_value("immediate_value_yen"),
      success_probability: decimal_value("success_probability", min: 0, max: 1),
      strategic_value_score: integer_value("strategic_value_score", min: 0, max: 100),
      risk_reduction_score: integer_value("risk_reduction_score", min: 0, max: 100),
      confidence_score: integer_value("confidence_score", min: 0, max: 100),
      data_confidence_score: integer_value("data_confidence_score", min: 0, max: 100),
      expected_hours: decimal_value("expected_hours", min: 0),
      cost_yen: integer_value("cost_yen", min: 0),
      evaluation_reason: string_value("evaluation_reason"),
      execution_prompt: string_value("execution_prompt")
    }
  end

  private

  attr_reader :attributes

  def action_type
    value = string_value("action_type")
    return value if ActionCandidate::ACTION_TYPES.include?(value)

    "other"
  end

  def string_value(key)
    attributes[key].to_s.strip
  end

  def integer_value(key, min: nil, max: nil)
    clamp(attributes[key].to_i, min:, max:)
  end

  def decimal_value(key, min: nil, max: nil)
    clamp(BigDecimal(attributes[key].to_s), min:, max:)
  end

  def clamp(value, min:, max:)
    value = min if min && value < min
    value = max if max && value > max
    value
  end
end
