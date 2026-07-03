module Admin
  class ApprovalLogsController < ApplicationController
    def index
      @action = params[:action_filter].presence_in(ApprovalLog::ACTIONS)
      @approval_logs = ApprovalLog
        .includes(:business)
        .for_action(@action)
        .recent
        .limit(200)
    end
  end
end
