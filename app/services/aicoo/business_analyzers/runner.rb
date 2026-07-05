module Aicoo
  module BusinessAnalyzers
    class Runner
      ANALYZERS = {
        "seo_media" => "Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer",
        "content_media" => "Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer",
        "directory" => "Aicoo::BusinessAnalyzers::SeoBusinessAnalyzer"
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(business:, today: Date.current)
        @business = business
        @today = today.to_date
      end

      def call
        analyzer_class = analyzer_class_for(business.business_type)
        return unhandled_result unless analyzer_class

        analyzer_class.call(business:, today:)
      end

      private

      attr_reader :business, :today

      def analyzer_class_for(business_type)
        ANALYZERS[business_type.to_s]&.constantize
      end

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
