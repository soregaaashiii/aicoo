module Admin
  class LovableController < ApplicationController
    def show
      @result = Aicoo::Lovable::PipelineDiagnostic.new(probe: params[:probe] == "1").call
      @latest_runs = AicooLabGenerationRun.where(generation_type: "lp_generation").recent.select do |run|
        run.metadata.to_h["pipeline"] == "lovable"
      end.first(50)
    end
  end
end
