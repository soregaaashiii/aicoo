module Aicoo
  module UniversalAnalysisEngine
    class StrategyRanker
      def self.call(candidates)
        new(candidates).call
      end

      def initialize(candidates)
        @candidates = Array(candidates)
      end

      def call
        candidates.sort_by { |candidate| -candidate.score.to_d }
      end

      private

      attr_reader :candidates
    end
  end
end
