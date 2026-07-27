module Aicoo
  class LovableLandingPageGenerationJob < ApplicationJob
    queue_as :default

    def perform(generation_run_id)
      run = AicooLabGenerationRun.find_by(id: generation_run_id)
      return unless run
      return unless run.metadata.to_h["lovable_execution_mode"] == "lovable_mcp"

      Aicoo::Lovable::LandingPagePipeline.new.execute!(run)
    rescue StandardError => e
      Rails.logger.error("[LovableMCP] run_id=#{generation_run_id} #{e.class}: #{e.message}")
    end
  end
end
