module Aicoo
  class OwnerHomeSummary
    Result = Data.define(
      :next_action,
      :execution_ready_count,
      :result_registration_count,
      :pending_calibration_count,
      :explore_review_count,
      :pending_opportunities_count,
      :top_pending_opportunity,
      :today_queue_count,
      :today_queue_completed_count,
      :top_queue_item,
      :daily_run_status,
      :learning_status,
      :summary_message
    )

    def initialize(owner_focus_home: nil, today_board: nil, daily_run_health: nil, learning_report: nil, explore_daily_routine: nil)
      @owner_focus_home = owner_focus_home
      @today_board = today_board
      @daily_run_health = daily_run_health
      @learning_report = learning_report
      @explore_daily_routine = explore_daily_routine
    end

    def call
      Result.new(
        next_action: today_board.items.first || owner_execution_queue_summary.top_item,
        execution_ready_count: ActionExecution.ready.count,
        result_registration_count: ActionExecution.completed_without_result.count,
        pending_calibration_count: ActionPredictionCalibration.where(approval_status: "pending").count,
        explore_review_count: explore_review_count,
        pending_opportunities_count: pending_opportunities_count,
        top_pending_opportunity: top_pending_opportunity,
        today_queue_count: owner_execution_queue_summary.pending_count,
        today_queue_completed_count: owner_execution_queue_summary.completed_count,
        top_queue_item: owner_execution_queue_summary.top_item,
        daily_run_status: daily_run_status,
        learning_status: learning_status,
        summary_message: summary_message
      )
    end

    private

    attr_reader :owner_focus_home

    def today_board
      @today_board ||= TodayActionBoard.new(mode: "revenue", limit: 20).call
    end

    def daily_run_health
      @daily_run_health ||= DailyRunHealthSummary.new.call
    end

    def learning_report
      @learning_report ||= LearningLoopQualityReport.new.call
    end

    def explore_daily_routine
      @explore_daily_routine ||= ExploreDailyRoutine.new.call
    end

    def owner_execution_queue_summary
      @owner_execution_queue_summary ||= OwnerExecutionQueueSummary.new.call
    end

    def daily_run_status
      case daily_run_health.health_status
      when "healthy"
        "Healthy"
      when "attention", "warning"
        "Warning"
      else
        "Critical"
      end
    end

    def learning_status
      case learning_report.learning_trend
      when "improving"
        "Improving"
      when "declining"
        "Declining"
      else
        "Stable"
      end
    end

    def explore_review_count
      explore_daily_routine.new_observation_count + pending_opportunities_count
    end

    def pending_opportunities_count
      OpportunityDiscoveryItem.where(status: "pending").count
    end

    def top_pending_opportunity
      @top_pending_opportunity ||= OpportunityDiscoveryItem.where(status: "pending").top_ranked.first
    end

    def summary_message
      return "Todayの最上位Actionを処理してください。" if today_board.items.any?
      return "今日の実行キューに#{owner_execution_queue_summary.pending_count}件あります。" if owner_execution_queue_summary.pending_count.positive?
      return "Exploreで見つかったOpportunityの確認待ちがあります。" if pending_opportunities_count.positive?

      "今すぐ処理すべきタスクはありません。"
    end
  end
end
