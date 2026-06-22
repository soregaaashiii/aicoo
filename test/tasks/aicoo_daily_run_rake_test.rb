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

  test "daily_run task calls runner" do
    called = false
    daily_run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "success")

    with_daily_runner_stub(->(target_date:, source:) {
      called = true
      assert_equal Date.new(2026, 6, 21), target_date
      assert_equal "manual", source
      daily_run
    }) do
      capture_io do
        Rake::Task["aicoo:daily_run"].invoke("2026-06-21")
      end
    end

    assert called
  end

  test "daily_run task without date calls scheduler as cron" do
    called = false
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "cron")

    with_scheduler_stub(->(source:) {
      called = true
      assert_equal "cron", source
      daily_run
    }) do
      capture_io do
        Rake::Task["aicoo:daily_run"].invoke
      end
    end

    assert called
  end

  private

  def with_daily_runner_stub(replacement)
    original = AicooDailyRunner.method(:run!)
    AicooDailyRunner.define_singleton_method(:run!) { |*args, **kwargs| replacement.call(*args, **kwargs) }
    yield
  ensure
    AicooDailyRunner.define_singleton_method(:run!) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
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
