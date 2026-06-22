module Owner
  class DashboardController < ApplicationController
    def show
      @mode = params[:mode].presence_in(%w[balanced revenue learning]) || "balanced"
      @dashboard_summary = DashboardSummaryService.new(owner_mode: @mode).call
    end
  end
end
