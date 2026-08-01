class AicooOperationStatusesController < ApplicationController
  skip_before_action :load_daily_run_execution_status, :load_long_running_operation_monitor

  def show
    daily_run_status = Aicoo::DailyRunExecutionStatus.call(include_latest: false)
    monitor = Aicoo::LongRunningOperationMonitor.new(
      running_only: true,
      include_daily_runs: daily_run_status.nil?
    ).call

    render partial: "shared/operation_status_panel",
           locals: {
             monitor:,
             daily_run_status:,
             refresh_url: aicoo_operation_status_path
           }
  rescue StandardError => e
    Rails.logger.warn("Operation status unavailable: #{e.class}: #{e.message}")
    render partial: "shared/operation_status_panel",
           locals: {
             monitor: nil,
             daily_run_status: nil,
             refresh_url: aicoo_operation_status_path
           }
  end
end
