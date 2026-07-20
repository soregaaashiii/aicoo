module Aicoo
  class LovableLandingPageGenerationJob < ApplicationJob
    queue_as :default

    def perform(generation_run_id)
      Rails.logger.info(
        "[Lovable] skipped legacy MCP generation run_id=#{generation_run_id} launch_route=build_with_url"
      )
    end
  end
end
