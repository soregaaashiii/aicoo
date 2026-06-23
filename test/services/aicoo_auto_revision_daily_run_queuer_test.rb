require "test_helper"

class AicooAutoRevisionDailyRunQueuerTest < ActiveSupport::TestCase
  setup do
    AutoRevisionQueueRun.delete_all
    AutoRevisionTask.delete_all
    AicooAutoRevisionSetting.delete_all
    ActionCandidate.update_all(status: "done")
  end

  test "does not run when setting is disabled" do
    AicooAutoRevisionSetting.current.update!(enabled: false)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal false, result.ran
    assert_equal "disabled", result.reason
    assert_equal 0, AutoRevisionQueueRun.count
    assert_equal 0, AutoRevisionTask.count
  end

  test "runs when enabled and creates queue run" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal true, result.ran
    assert_equal 1, AutoRevisionTask.count
    assert_equal 1, AutoRevisionQueueRun.count
    assert_equal daily_run, result.queue_run.aicoo_daily_run
    assert_equal 1, result.queue_run.generated_tasks_count
    assert AicooAutoRevisionSetting.current.last_auto_queue_at.present?
  end

  test "respects max tasks per run" do
    AicooAutoRevisionSetting.current.update!(enabled: true, max_tasks_per_run: 2)
    daily_run = create_daily_run
    4.times { |index| create_candidate(title: "SEOタイトル改善 #{index}", execution_prompt: "SEOタイトルを改善してください。") }

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 2, result.queue_run.generated_tasks_count
    assert_equal 2, AutoRevisionTask.count
  end

  test "respects minimum final score" do
    AicooAutoRevisionSetting.current.update!(enabled: true, minimum_final_score: 99_999)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 0, result.queue_run.generated_tasks_count
    assert_equal 0, AutoRevisionTask.count
  end

  test "excludes high risk candidates" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "DB migrationで認証tokenを変更", execution_prompt: "DB migrationでcredentialを変更してください。")

    result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_equal 0, result.queue_run.generated_tasks_count
    assert_equal 1, result.queue_run.high_risk_candidates_count
    assert_equal 0, AutoRevisionTask.count
  end

  test "does not create twice for same daily run" do
    AicooAutoRevisionSetting.current.update!(enabled: true)
    daily_run = create_daily_run
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    first_result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)

    assert_no_difference("AutoRevisionTask.count") do
      second_result = AicooAutoRevisionDailyRunQueuer.new.call(daily_run:)
      assert_equal false, second_result.ran
      assert_equal "already_run", second_result.reason
      assert_equal first_result.queue_run, second_result.queue_run
    end
  end

  private

  def create_daily_run
    AicooDailyRun.create!(target_date: Date.yesterday, status: "success", source: "manual", started_at: Time.current)
  end

  def create_candidate(title:, execution_prompt:)
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type: "seo_improvement",
      status: "idea",
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt:
    )
  end
end
