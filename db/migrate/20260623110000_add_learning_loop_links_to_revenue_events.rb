class AddLearningLoopLinksToRevenueEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :revenue_events, :action_candidate, foreign_key: true
    add_reference :revenue_events, :action_result, foreign_key: true
    add_reference :revenue_events, :action_execution_log, foreign_key: true
  end
end
