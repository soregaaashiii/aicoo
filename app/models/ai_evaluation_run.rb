class AiEvaluationRun < ApplicationRecord
  self.ignored_columns += [ "model_name" ]

  belongs_to :business

  validates :input_data, :prompt, :raw_response, presence: true
  validates :created_action_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
