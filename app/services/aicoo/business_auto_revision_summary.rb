module Aicoo
  class BusinessAutoRevisionSummary
    Result = Data.define(
      :automatic_business_count,
      :approval_waiting_count,
      :today_success_count,
      :today_failure_count,
      :today_stopped_count,
      :recent_logs
    )

    def call
      Result.new(
        automatic_business_count: Business.real_businesses.where(auto_revision_mode: "automatic").count,
        approval_waiting_count: AutoRevisionTask.where(status: "waiting_approval").count,
        today_success_count: AutoRevisionRunLog.today.where(status: "succeeded").count,
        today_failure_count: AutoRevisionRunLog.today.where(status: "failed").count,
        today_stopped_count: AutoRevisionRunLog.today.where(status: "precheck_failed").count,
        recent_logs: AutoRevisionRunLog.includes(:business, :auto_revision_task).recent.limit(5)
      )
    end
  end
end
