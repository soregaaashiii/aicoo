module Admin
  class AutoRevisionRunLogsController < ApplicationController
    def rollback
      log = AutoRevisionRunLog.find(params.expect(:id))
      log.mark_rolled_back!(message: "Rollback requested from SYSTEM")

      redirect_back fallback_location: business_path(log.business),
                    notice: "#{log.business.name} のRollbackをリクエストしました。"
    end
  end
end
