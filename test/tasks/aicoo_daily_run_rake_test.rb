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
    daily_run = AicooDailyRun.create!(target_date: Date.new(2026, 6, 21), status: "succeeded")

    with_daily_runner_stub(->(target_date:) {
      called = true
      assert_equal Date.new(2026, 6, 21), target_date
      daily_run
    }) do
      capture_io do
        Rake::Task["aicoo:daily_run"].invoke("2026-06-21")
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
end
