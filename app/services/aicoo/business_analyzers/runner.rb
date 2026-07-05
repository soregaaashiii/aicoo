module Aicoo
  module BusinessAnalyzers
    class Runner
      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current)
        @business = business
        @today = today.to_date
      end

      def call
        Aicoo::BusinessAnalyzers::GenericOpportunityAnalyzer.call(business:, today:)
      end

      private

      attr_reader :business, :today

      def unhandled_result
        Result.new(
          business:,
          analyzer: nil,
          created: [],
          skipped: [],
          issues: [],
          opportunities: [],
          handled: false
        )
      end
    end
  end
end
