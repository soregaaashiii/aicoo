module Admin
  module AicooLab
    class IndependentLearningController < ApplicationController
      def index
        @result = Aicoo::IndependentActivityLearningDiagnostic.new(limit: 2_000).call
        @candidate_generation_result = Aicoo::IndependentActivityCandidateGenerator.call(limit: 2_000)
      end
    end
  end
end
