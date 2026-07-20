module Admin
  module AicooLab
    class LpLearningController < ApplicationController
      def index
        @business_summaries = {}
        @rows = build_rows
      end

      private

      def build_rows
        Business.real_businesses.filter_map do |business|
          repository = Aicoo::Lovable::VersionRepository.new(business:)
          comparison = Aicoo::Lovable::LandingPageLearningComparison.new(business:, repository:).call
          @business_summaries[business.id] = comparison
          repository.all.filter_map do |run|
            next unless run.metadata.to_h.dig("publication", "published") == true

            learning = Aicoo::Lovable::LearningSummary.new(business:, generation_run: run).call
            {
              business:,
              run:,
              learning:,
              publication: run.metadata.to_h["publication"].to_h,
              best: comparison.best&.run&.id == run.id,
              worst: comparison.worst&.run&.id == run.id,
              analysis: run.metadata.to_h["landing_page_improvement_analysis"].to_h
            }
          end
        end.flatten.sort_by { |row| row[:publication]["published_at"].to_s }.reverse
      end
    end
  end
end
