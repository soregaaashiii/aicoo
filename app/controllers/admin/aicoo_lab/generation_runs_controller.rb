module Admin
  module AicooLab
    class GenerationRunsController < ApplicationController
      def index
        @generation_runs = AicooLabGenerationRun.recent
      end

      def show
        @generation_run = AicooLabGenerationRun.find(params.expect(:id))
      end
    end
  end
end
