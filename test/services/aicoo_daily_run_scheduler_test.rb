require "test_helper"

class AicooDailyRunSchedulerTest < ActiveSupport::TestCase
  setup do
    AicooDailyRun.where(target_date: Date.yesterday).delete_all
  end

  test "cron run executes when due and not successful today" do
    setting = AicooDailyRunSetting.create!(
      enabled: true,
      run_hour: 0,
      run_minute: 0,
      timezone: "Asia/Tokyo",
      catch_up_enabled: true,
      retry_until_success: true,
      max_retry_per_day: 10
    )
    make_due!(setting)
    run = nil

    with_runner_stub(->(target_date:, source:) {
      assert_equal Date.yesterday, target_date
      assert_equal "cron", source
      run = AicooDailyRun.create!(target_date:, status: "success", source:)
      run
    }) do
      result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

      assert_equal run, result
    end
  end

  test "does not start duplicate running run" do
    setting = AicooDailyRunSetting.create!(run_hour: 0, run_minute: 0)
    make_due!(setting)
    running = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "cron", started_at: Time.current)

    with_runner_stub(->(**) { raise "should not run" }) do
      assert_equal running, AicooDailyRunScheduler.new(setting:).check!(source: "cron")
    end
  end

  test "marks stuck run and allows retry" do
    setting = AicooDailyRunSetting.create!(run_hour: 0, run_minute: 0)
    make_due!(setting)
    stuck = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "cron", started_at: 31.minutes.ago)
    retry_run = nil

    with_runner_stub(->(target_date:, source:) {
      retry_run = AicooDailyRun.create!(target_date:, status: "success", source:)
      retry_run
    }) do
      result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

      assert_equal retry_run, result
    end

    assert_equal "stuck", stuck.reload.status
  end

  test "respects max retry per day" do
    setting = AicooDailyRunSetting.create!(run_hour: 0, run_minute: 0, max_retry_per_day: 1)
    make_due!(setting)
    AicooDailyRun.create!(target_date: Date.yesterday, status: "failed", source: "cron")

    with_runner_stub(->(**) { raise "should not run" }) do
      assert_no_difference -> { AicooDailyRun.count } do
        result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

        assert_equal "schedule_check", result.status
        assert_equal "retry_limit_reached", result.reason
      end
    end
  end

  test "does not create daily run row when cron is not due" do
    setting = AicooDailyRunSetting.create!(enabled: true, run_hour: 23, run_minute: 59)
    setting.define_singleton_method(:scheduled_time_for) { |_date = Date.current| 1.hour.from_now }

    with_runner_stub(->(**) { raise "should not run" }) do
      assert_no_difference -> { AicooDailyRun.count } do
        result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

        assert_equal "schedule_check", result.status
        assert_equal "not_due", result.reason
      end
    end
  end

  test "does not create daily run row when already successful today" do
    setting = AicooDailyRunSetting.create!(run_hour: 0, run_minute: 0)
    make_due!(setting)
    AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "cron")

    with_runner_stub(->(**) { raise "should not run" }) do
      assert_no_difference -> { AicooDailyRun.count } do
        result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

        assert_equal "schedule_check", result.status
        assert_equal "already_success", result.reason
      end
    end
  end

  test "uses Asia Tokyo date for due and target date around UTC midnight" do
    setting = AicooDailyRunSetting.create!(
      enabled: true,
      run_hour: 0,
      run_minute: 15,
      timezone: "Asia/Tokyo",
      catch_up_enabled: true,
      retry_until_success: true,
      max_retry_per_day: 10
    )
    run = nil

    travel_to Time.utc(2026, 6, 27, 15, 30) do
      with_runner_stub(->(target_date:, source:) {
        assert_equal Date.new(2026, 6, 27), target_date
        assert_equal "cron", source
        run = AicooDailyRun.create!(target_date:, status: "success", source:)
        run
      }) do
        result = AicooDailyRunScheduler.new(setting:).check!(source: "cron")

        assert_equal run, result
      end
    end
  end

  test "application displays times in Japan while keeping database time in UTC" do
    assert_equal "Asia/Tokyo", Time.zone.name
    assert_equal :utc, Rails.application.config.active_record.default_timezone
  end

  private

  def make_due!(setting)
    setting.define_singleton_method(:scheduled_time_for) { |_date = Date.current| 1.hour.ago }
  end

  def with_runner_stub(replacement)
    original = AicooDailyRunner.method(:run!)
    AicooDailyRunner.define_singleton_method(:run!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    AicooDailyRunner.define_singleton_method(:run!) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
