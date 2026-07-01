module Aicoo
  class CodexSubmissionSummary
    Summary = Data.define(
      :ready_count,
      :draft_count,
      :failed_count,
      :submitted_today_count,
      :blocked_count
    )

    def call
      Summary.new(
        ready_count: CodexSubmission.where(status: "ready").count,
        draft_count: CodexSubmission.where(status: "draft").count,
        failed_count: CodexSubmission.where(status: "failed").count,
        submitted_today_count: CodexSubmission.where(status: "submitted", submitted_at: Time.zone.today.all_day).count,
        blocked_count: CodexSubmission.where(status: "draft").where.not(error_message: [ nil, "" ]).count
      )
    end
  end
end
