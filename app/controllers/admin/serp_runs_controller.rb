module Admin
  class SerpRunsController < ApplicationController
    def show
      @serp_run = SerpRun.find(params[:id])
      @analyses_by_query_id = @serp_run
        .serp_analyses
        .includes(:business, :serp_results)
        .index_by { |analysis| analysis.raw_summary.to_h["serp_query_id"].to_i }
    end
  end
end
