module Admin
  class AutoBuildTasksController < ApplicationController
    def index
      @summary = Aicoo::ResourceAwareAutoBuildSummary.new.call
      @auto_build_tasks = AutoBuildTask.includes(:business, :auto_revision_task).recent.limit(50)
    end

    def show
      @auto_build_task = AutoBuildTask.includes(:business, :auto_revision_task).find(params[:id])
    end
  end
end
