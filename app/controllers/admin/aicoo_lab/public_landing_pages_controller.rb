module Admin
  module AicooLab
    class PublicLandingPagesController < ApplicationController
      def index
        @status_filter = params[:public_status].presence
        @landing_pages = AicooLabLandingPage
                         .with_public_slug
                         .includes(:aicoo_lab_experiment)
                         .where(public_status: visible_statuses)
                         .order(updated_at: :desc)
      end

      private

      def visible_statuses
        return @status_filter if @status_filter.in?(%w[published paused archived])

        %w[published paused archived]
      end
    end
  end
end
