module Owner
  class LearningReportsController < ApplicationController
    def show
      @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
      @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
      @learning_report_recommendations = Aicoo::LearningReportRecommendation.new(
        quality_report: @learning_loop_quality_report,
        discovery_source_report: @discovery_source_performance_report
      ).call
      @practicality_summary = Aicoo::PracticalitySummary.new.call
      candidates = ActionCandidate.includes(:business).to_a
      decision_logs = OwnerDecisionLog.last_30_days.to_a
      @evidence_summary = Aicoo::EvidenceSummary.new(candidates:, decision_logs:).call
      @business_playbook_summary = Aicoo::BusinessPlaybookSummary.new.call
      @business_integration_health = Aicoo::BusinessIntegrationHealth.new.call
      @owner_decision_summary = Aicoo::OwnerDecisionSummary.new.call
      @strategic_learning_report = Aicoo::StrategicLearningReport.new(candidates:).call
      @engagement_summary = Aicoo::EngagementSummary.new.call
    end
  end
end
