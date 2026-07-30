module Owner
  class DashboardController < ApplicationController
    def show
      Aicoo::MemoryDiagnostics.measure("Owner::DashboardController#show", context: memory_diagnostics_context) do
        @mode = params[:mode].presence_in(%w[balanced revenue learning]) || "balanced"
        @today_board = Aicoo::MemoryDiagnostics.measure("Owner::DashboardController#show.today_board", context: memory_diagnostics_context(mode: @mode)) do
          Aicoo::TodayActionBoard.new(
            mode: @mode,
            page: params[:home_actions_page],
            page_param: :home_actions_page
          ).call
        end
        @dashboard_summary = Aicoo::MemoryDiagnostics.measure("Owner::DashboardController#show.dashboard_summary", context: memory_diagnostics_context(mode: @mode)) do
          DashboardSummaryService.new(owner_mode: @mode, current_mode: "ceo").call_for_owner_home
        end
        @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
        @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
        @learning_report_recommendations = Aicoo::LearningReportRecommendation.new(
          quality_report: @learning_loop_quality_report,
          discovery_source_report: @discovery_source_performance_report
        ).call
        @opportunity_discovery_summary = Aicoo::OpportunityDiscoverySummary.new.call_for_owner_home
        @opportunity_focus_queue = Aicoo::OpportunityFocusQueue.new.call
        @explore_summary = Aicoo::ExploreSummary.new.call_for_owner_home
        @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
        @analysis_monitor = Aicoo::AnalysisMonitor.new.call_for_owner_home
      end
    end
  end
end
