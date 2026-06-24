module Owner
  class LearningReportsController < ApplicationController
    def show
      @learning_loop_quality_report = Aicoo::LearningLoopQualityReport.new.call
    end
  end
end
