module Aicoo
  class BusinessAutoRevisionSummary
    Result = Data.define(
      :automatic_business_count,
      :automatic_deploy_business_count,
      :approval_waiting_count,
      :deploy_approval_waiting_count,
      :today_success_count,
      :today_failure_count,
      :today_stopped_count,
      :deploy_failed_count,
      :rollback_available_count,
      :recent_logs
    )

    def call
      Result.new(
        automatic_business_count: Business.real_businesses.where(auto_revision_mode: "automatic").count,
        automatic_deploy_business_count: Business.real_businesses.where(auto_deploy_mode: "automatic").count,
        approval_waiting_count: AutoRevisionTask.where(status: "waiting_approval").count,
        deploy_approval_waiting_count: AutoRevisionRunLog.where(status: "deploy_pending", deploy_result: [ nil, "" ]).count,
        today_success_count: AutoRevisionRunLog.today.where(status: "succeeded").count,
        today_failure_count: AutoRevisionRunLog.today.where(status: "failed").count,
        today_stopped_count: AutoRevisionRunLog.today.where(status: "precheck_failed").count,
        deploy_failed_count: AutoRevisionRunLog.where(deploy_result: "failed").count,
        rollback_available_count: AutoRevisionRunLog.where.not(base_commit_sha: [ nil, "" ]).where(rollback_status: [ nil, "" ]).count,
        recent_logs: AutoRevisionRunLog.includes(:business, :auto_revision_task).recent.limit(5)
      )
    end
  end
end
