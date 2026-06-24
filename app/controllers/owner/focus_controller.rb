module Owner
  class FocusController < ApplicationController
    def show
      @owner_focus_home = Aicoo::OwnerFocusHome.new.call
      @top_task = @owner_focus_home.top_task
      @explore_daily_routine = Aicoo::ExploreDailyRoutine.new.call
      @owner_home_summary = Aicoo::OwnerHomeSummary.new(
        owner_focus_home: @owner_focus_home,
        explore_daily_routine: @explore_daily_routine
      ).call
    end
  end
end
