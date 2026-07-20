module Aicoo
  class LovableLandingPageGenerationJob < ApplicationJob
    queue_as :default

    def perform(generation_run_id)
      Aicoo::Lovable::LandingPagePipeline.new.execute!(AicooLabGenerationRun.find(generation_run_id))
    end
  end
end
