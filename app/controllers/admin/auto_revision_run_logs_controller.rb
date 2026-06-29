module Admin
  class AutoRevisionRunLogsController < ApplicationController
    def rollback
      log = AutoRevisionRunLog.find(params.expect(:id))
      log.mark_rolled_back!(message: "Rollback requested from SYSTEM")
      log.update!(
        metadata: log.metadata.to_h.merge(
          "deploy_event" => "RollbackRequested",
          "rollback_requested_at" => Time.current.iso8601
        )
      )

      redirect_back fallback_location: business_path(log.business),
                    notice: "#{log.business.name} のRollbackをリクエストしました。"
    end
  end
end
