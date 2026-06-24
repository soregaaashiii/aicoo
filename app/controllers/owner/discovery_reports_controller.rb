module Owner
  class DiscoveryReportsController < ApplicationController
    def show
      @discovery_source_performance_report = Aicoo::DiscoverySourcePerformanceReport.new.call
    end
  end
end
