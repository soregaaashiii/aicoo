module Owner
  class DashboardController < ApplicationController
    def show
      @mode = params[:mode].presence_in(%w[balanced revenue learning]) || "balanced"
      @dashboard_summary = DashboardSummaryService.new(owner_mode: @mode, current_mode: "ceo").call
    end
  end
end
