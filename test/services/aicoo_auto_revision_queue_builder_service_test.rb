require "test_helper"

class AicooAutoRevisionQueueBuilderServiceTest < ActiveSupport::TestCase
  setup do
    AutoRevisionTask.delete_all
    ActionCandidate.update_all(status: "done")
  end

  test "creates auto revision task from eligible action candidate" do
    candidate = create_candidate(title: "SEOタイトルを改善する", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 1, result.created_count
    task = AutoRevisionTask.last
    assert_equal candidate, task.action_candidate
    assert_equal "waiting_approval", task.status
    assert_equal "low", task.risk_level
    assert_equal candidate.reload.final_score.to_d, task.priority_score
  end

  test "excludes candidate without execution prompt" do
    create_candidate(title: "promptなし", execution_prompt: nil)

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "excludes inactive candidates" do
    %w[archived rejected done].each do |status|
      create_candidate(title: "#{status} candidate", status:, execution_prompt: "文言を改善してください。")
    end

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "excludes high risk candidates but reports them" do
    candidate = create_candidate(
      title: "DB migrationで認証credentialを変更する",
      execution_prompt: "DB migrationを追加し、tokenを扱う設定を変更してください。"
    )

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 0, result.created_count
    assert_equal [ candidate ], result.high_risk_candidates
  end

  test "does not duplicate existing unfinished auto revision task" do
    candidate = create_candidate(title: "表示文言改善", execution_prompt: "表示文言を改善してください。")
    AutoRevisionTask.from_action_candidate(candidate)

    assert_no_difference("AutoRevisionTask.count") do
      AicooAutoRevisionQueueBuilderService.new.call
    end
  end

  test "creates at most five tasks" do
    7.times do |index|
      create_candidate(title: "SEOタイトル改善 #{index}", execution_prompt: "SEOタイトルを改善してください。")
    end

    result = AicooAutoRevisionQueueBuilderService.new.call

    assert_equal 5, result.created_count
    assert_equal 5, AutoRevisionTask.count
  end

  test "respects custom minimum final score" do
    create_candidate(title: "SEOタイトル改善", execution_prompt: "SEOタイトルを改善してください。")

    result = AicooAutoRevisionQueueBuilderService.new(minimum_final_score: 99_999).call

    assert_equal 0, result.created_count
    assert_equal 0, AutoRevisionTask.count
  end

  test "can exclude medium risk candidates" do
    create_candidate(title: "管理画面の集計を改善する", execution_prompt: "serviceとviewを改修してください。")

    result = AicooAutoRevisionQueueBuilderService.new(allow_medium_risk: false).call

    assert_equal 0, result.created_count
    assert_equal 0, AutoRevisionTask.count
  end

  private

  def create_candidate(title:, execution_prompt:, status: "idea")
    ActionCandidate.create!(
      business: businesses(:suelog),
      title:,
      action_type: "seo_improvement",
      status:,
      immediate_value_yen: 20_000,
      success_probability: 1,
      expected_hours: 1,
      execution_prompt:
    )
  end
end
