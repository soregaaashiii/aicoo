module Admin
  module AicooLab
    class IndependentLearningController < ApplicationController
      def index
        @result = Aicoo::IndependentActivityLearningDiagnostic.new(limit: 2_000).call
      end
    end
  end
end
