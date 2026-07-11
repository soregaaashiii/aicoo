require "test_helper"

class AicooDailyRunnerSuelogTest < ActiveSupport::TestCase
  test "suelog database steps skip safely when database url is missing" do
    business = businesses(:suelog)
    business.update!(project_key: "suelog", repository_name: "suelog")
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "test")
    runner = AicooDailyRunner.new(target_date: Date.yesterday, source: "test")

    without_suelog_database_url do
      assert_nothing_raised do
        runner.send(:run_suelog_database_steps!, daily_run)
      end
    end

    step = daily_run.aicoo_daily_run_steps.find_by!(step_name: "suelog_database_health_check")
    assert_equal "skipped", step.status
    assert_equal "missing_database_url", step.metadata["reason"]
  end

  private

  def without_suelog_database_url
    original = ENV["SUELOG_DATABASE_URL"]
    ENV.delete("SUELOG_DATABASE_URL")
    yield
  ensure
    ENV["SUELOG_DATABASE_URL"] = original if original
  end
end
