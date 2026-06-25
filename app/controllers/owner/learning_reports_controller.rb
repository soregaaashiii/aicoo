module Owner
  class LearningReportsController < ApplicationController
    def show
      @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
      @learning_report_recommendations = Aicoo::LearningReportRecommendation.new.call
      @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
      @owner_decision_summary = Aicoo::OwnerDecisionSummary.new.call
      @strategic_learning_report = Aicoo::StrategicLearningReport.new.call
    end
  end
end
