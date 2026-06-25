module Aicoo
  class StrategicPhilosophy
    WEIGHT_ATTRIBUTES = AicooSetting::STRATEGIC_WEIGHT_ATTRIBUTES

    attr_reader :setting

    def self.current
      new(AicooSetting.current)
    end

    def initialize(setting = AicooSetting.current)
      @setting = setting
    end

    def weights
      WEIGHT_ATTRIBUTES.index_with { |attribute| setting.public_send(attribute).to_i }
    end

    def total_weight
      weights.values.sum
    end

    def score(components)
      return 50.to_d if total_weight.zero?

      weighted_total = {
        long_term_profit_weight: components.fetch(:long_term_profit, 0),
        short_term_profit_weight: components.fetch(:short_term_profit, 0),
        learning_weight: components.fetch(:learning, 0),
        automation_weight: components.fetch(:automation, 0),
        exploration_weight: components.fetch(:exploration, 0)
      }.sum { |attribute, value| weights.fetch(attribute).to_d * clamp(value) }

      (weighted_total / total_weight.to_d).round(2)
    end

    private

    def clamp(value)
      [ [ value.to_d, 0.to_d ].max, 100.to_d ].min
    end
  end
end
