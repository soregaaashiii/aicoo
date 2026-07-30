module Admin
  class AicooRevenueController < ApplicationController
    def show
      @today_board = ::Aicoo::TodayActionBoard.new(mode: params[:mode]).call
    end

    private

    def planned_execution_keys
      ::AicooRevenueExecution.planned.pluck(:source_type, :source_id).map { |source_type, source_id| "#{source_type}:#{source_id}" }
    end
  end
end
