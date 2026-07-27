require "test_helper"

class AicooDailyRunTest < ActiveSupport::TestCase
  test "current step reuses a loaded step association" do
    run = AicooDailyRun.create!(
      target_date: Date.current,
      status: "running",
      source: "manual",
      started_at: 2.minutes.ago
    )
    older = run.aicoo_daily_run_steps.create!(
      step_name: "analytics_fetch",
      status: "running",
      started_at: 2.minutes.ago
    )
    latest = run.aicoo_daily_run_steps.create!(
      step_name: "action_generation",
      status: "running",
      started_at: 1.minute.ago
    )
    loaded_run = AicooDailyRun.includes(:aicoo_daily_run_steps).find(run.id)
    selects = 0
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      selects += 1 if payload[:sql].to_s.match?(/\ASELECT/)
    end

    current = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      loaded_run.current_step
    end

    assert_equal latest, current
    assert_not_equal older, current
    assert_equal 0, selects
  end
end
