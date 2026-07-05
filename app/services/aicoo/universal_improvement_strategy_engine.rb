module Aicoo
  class UniversalImprovementStrategyEngine
    def self.call(...)
      new(...).call
    end

    def initialize(opportunity)
      @opportunity = opportunity
    end

    def call
      Aicoo::ActionDecisionEngine.new(opportunity).call
    end

    private

    attr_reader :opportunity
  end
end
