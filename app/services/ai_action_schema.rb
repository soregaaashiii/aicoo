class AiActionSchema
  ACTION_PROPERTIES = {
    title: { type: "string" },
    description: { type: "string" },
    action_type: { type: "string", enum: ActionCandidate::ACTION_TYPES },
    immediate_value_yen: { type: "integer", minimum: 0 },
    success_probability: { type: "number", minimum: 0, maximum: 1 },
    strategic_value_score: { type: "integer", minimum: 0, maximum: 100 },
    risk_reduction_score: { type: "integer", minimum: 0, maximum: 100 },
    confidence_score: { type: "integer", minimum: 0, maximum: 100 },
    data_confidence_score: { type: "integer", minimum: 0, maximum: 100 },
    expected_hours: { type: "number", minimum: 0 },
    cost_yen: { type: "integer", minimum: 0 },
    evaluation_reason: { type: "string" },
    execution_prompt: { type: "string" }
  }.freeze

  ACTION_REQUIRED = ACTION_PROPERTIES.keys.map(&:to_s).freeze

  def self.actions_schema(action_count: 5)
    {
      type: "object",
      additionalProperties: false,
      properties: {
        actions: {
          type: "array",
          minItems: action_count,
          maxItems: action_count,
          items: action_schema
        }
      },
      required: [ "actions" ]
    }
  end

  def self.cross_business_actions_schema(action_count: 10)
    {
      type: "object",
      additionalProperties: false,
      properties: {
        actions: {
          type: "array",
          minItems: 1,
          maxItems: action_count,
          items: cross_business_action_schema
        }
      },
      required: [ "actions" ]
    }
  end

  def self.reevaluation_schema
    {
      type: "object",
      additionalProperties: false,
      properties: {
        action: action_schema
      },
      required: [ "action" ]
    }
  end

  def self.action_schema
    {
      type: "object",
      additionalProperties: false,
      properties: ACTION_PROPERTIES.deep_stringify_keys,
      required: ACTION_REQUIRED
    }
  end

  def self.cross_business_action_schema
    action_schema.deep_dup.tap do |schema|
      schema[:properties]["business_id"] = { type: "integer" }
      schema[:required] = [ "business_id", *schema[:required] ]
    end
  end
end
