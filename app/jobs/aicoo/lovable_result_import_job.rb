module Aicoo
  class LovableResultImportJob < ApplicationJob
    queue_as :default

    def perform(generation_run_id)
      run = AicooLabGenerationRun.find_by(id: generation_run_id)
      return unless run

      Aicoo::Lovable::ResultRepositoryImporter.new.call(generation_run: run)
    rescue StandardError => e
      Rails.logger.error("[LovableResultImportJob] run_id=#{generation_run_id} #{e.class}: #{e.message}")
    end
  end
end
