require "test_helper"
require "rake"

class AicooDailyRunRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:daily_run")
    Rake::Task["aicoo:daily_run"].reenable
  end

  test "daily_run task exists" do
    assert Rake::Task.task_defined?("aicoo:daily_run")
  end

  test "daily_run task does not call scheduler when cron env is disabled" do
    called = false

    with_env("AICOO_DAILY_RUN_ENABLED", nil) do
      with_scheduler_stub(->(source:) {
        called = true
        raise "scheduler should not be called"
      }) do
        out, = capture_io do
          Rake::Task["aicoo:daily_run"].invoke
        end

        assert_includes out, "cron disabled"
      end
    end

    assert_not called
  end

  test "daily_run task calls scheduler as cron when cron env is enabled" do
    called = false
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "cron")

    with_env("AICOO_DAILY_RUN_ENABLED", "true") do
      with_scheduler_stub(->(source:) {
        called = true
        assert_equal "cron", source
        daily_run
      }) do
        out, = capture_io do
          Rake::Task["aicoo:daily_run"].invoke
        end

        assert_includes out, "daily_run_id=#{daily_run.id}"
        assert_includes out, "status=success"
      end
    end

    assert called
  end

  test "daily_run task delegates successful today and running checks to scheduler" do
    called = false
    skipped_run = AicooDailyRun.create!(
      target_date: Date.current,
      status: "skipped",
      source: "cron",
      run_log: "Daily Run skipped: already_success"
    )

    with_env("AICOO_DAILY_RUN_ENABLED", "true") do
      with_scheduler_stub(->(source:) {
        called = true
        assert_equal "cron", source
        skipped_run
      }) do
        out, = capture_io do
          Rake::Task["aicoo:daily_run"].invoke
        end

        assert_includes out, "status=skipped"
      end
    end

    assert called
  end

  private

  def with_env(key, value)
    previous = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end

  def with_scheduler_stub(replacement)
    original = AicooDailyRunScheduler.method(:check!)
    AicooDailyRunScheduler.define_singleton_method(:check!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    AicooDailyRunScheduler.define_singleton_method(:check!) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
