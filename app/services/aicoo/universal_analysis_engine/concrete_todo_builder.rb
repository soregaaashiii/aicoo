module Aicoo
  module UniversalAnalysisEngine
    class ConcreteTodoBuilder
      FORBIDDEN_PATTERNS = [
        /要具体化/,
        /検索需要があるテーマ/,
        /CVを改善/,
        /CV改善\z/,
        /SEO改善\z/,
        /SEOを改善/,
        /UXを改善/,
        /CTAを改善/,
        /デザインを改善/,
        /サイト改善/,
        /導線改善/,
        /TODOを具体化/,
        /記事を増やす/,
        /Analyzer/i
      ].freeze

      Result = Data.define(:valid, :summary, :errors) do
        def valid? = valid
      end

      def self.call(...)
        new(...).call
      end

      def initialize(summary:)
        @summary = summary.to_s.strip
      end

      def call
        errors = []
        errors << "blank_summary" if summary.blank?
        errors << "abstract_summary" if FORBIDDEN_PATTERNS.any? { |pattern| summary.match?(pattern) }

        Result.new(valid: errors.empty?, summary:, errors:)
      end

      private

      attr_reader :summary
    end
  end
end
