require "test_helper"
require "rake"

class AicooDailyRunRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:daily_run")
    Rake::Task["aicoo:daily_run"].reenable
    Rake::Task["aicoo:diagnose_daily_run_retry"].reenable if Rake::Task.task_defined?("aicoo:diagnose_daily_run_retry")
    Rake::Task["aicoo:daily_run_manual"].reenable if Rake::Task.task_defined?("aicoo:daily_run_manual")
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

  test "daily_run task calls scheduler as manual when source is manual" do
    called = false
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "manual")

    with_env("AICOO_DAILY_RUN_ENABLED", nil) do
      with_env("SOURCE", "manual") do
        with_scheduler_stub(->(source:) {
          called = true
          assert_equal "manual", source
          daily_run
        }) do
          out, = capture_io do
            Rake::Task["aicoo:daily_run"].invoke
          end

          assert_includes out, "source=manual"
          assert_includes out, "status=success"
        end
      end
    end

    assert called
  end

  test "daily_run task delegates successful today and running checks to scheduler" do
    called = false
    schedule_decision = AicooDailyRunScheduler::ScheduleDecision.new(
      status: "schedule_check",
      reason: "already_success",
      source: "cron",
      target_date: Date.current,
      message: "Daily Run schedule check: already_success"
    )

    with_env("AICOO_DAILY_RUN_ENABLED", "true") do
      with_scheduler_stub(->(source:) {
        called = true
        assert_equal "cron", source
        schedule_decision
      }) do
        out, = capture_io do
          Rake::Task["aicoo:daily_run"].invoke
        end

        assert_includes out, "reason=already_success"
        assert_not_includes out, "daily_run_id="
      end
    end

    assert called
  end

  test "cleanup_daily_run_schedule_checks is dry-run by default" do
    Rake::Task["aicoo:cleanup_daily_run_schedule_checks"].reenable
    schedule_check = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "skipped",
      source: "cron",
      run_log: "Daily Run skipped: not_due"
    )
    real_failed = AicooDailyRun.create!(
      target_date: Date.yesterday,
      status: "failed",
      source: "cron",
      run_log: "Daily Run failed"
    )

    out, = capture_io do
      Rake::Task["aicoo:cleanup_daily_run_schedule_checks"].invoke
    end

    assert_includes out, "mode=dry_run"
    assert_includes out, "schedule_checks_found=1"
    assert AicooDailyRun.exists?(schedule_check.id)
    assert AicooDailyRun.exists?(real_failed.id)
  end

  test "daily_run task records failed run and step when scheduler raises" do
    with_env("AICOO_DAILY_RUN_ENABLED", "true") do
      with_scheduler_stub(->(source:) {
        assert_equal "cron", source
        raise RuntimeError, "scheduler exploded"
      }) do
        assert_difference -> { AicooDailyRun.count }, 1 do
          assert_raises(RuntimeError) do
            capture_io do
              Rake::Task["aicoo:daily_run"].invoke
            end
          end
        end
      end
    end

    daily_run = AicooDailyRun.order(:created_at).last
    assert_equal "failed", daily_run.status
    assert_equal "cron", daily_run.source
    assert_includes daily_run.error_message, "scheduler exploded"

    step = daily_run.aicoo_daily_run_steps.find_by!(step_name: "cron_execution")
    assert_equal "failed", step.status
    assert_includes step.error_message, "scheduler exploded"
    assert_equal "render_cron", step.metadata["source"]
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
