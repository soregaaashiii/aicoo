module Owner
  class LearningReportsController < ApplicationController
    def show
      @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
      @learning_report_recommendations = Aicoo::LearningReportRecommendation.new.call
      @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
    end
  end
end
