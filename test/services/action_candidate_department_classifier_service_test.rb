require "test_helper"

class ActionCandidateDepartmentClassifierServiceTest < ActiveSupport::TestCase
  test "classifies revenue candidates from action type and title" do
    candidate = build_candidate(title: "吸えログの店舗登録とGSC分析を行う", action_type: "other")

    assert_equal "revenue", ActionCandidateDepartmentClassifierService.new.classify(candidate)
  end

  test "classifies lab candidates from title" do
    candidate = build_candidate(title: "LPテストで仮説検証を行う", action_type: "other")

    assert_equal "lab", ActionCandidateDepartmentClassifierService.new.classify(candidate)
  end

  test "classifies new business candidates from title" do
    candidate = build_candidate(title: "新規事業案の市場調査を行う", action_type: "other")

    assert_equal "new_business", ActionCandidateDepartmentClassifierService.new.classify(candidate)
  end

  test "general only mode does not overwrite existing department" do
    kept = create_candidate(title: "LPテストで仮説検証を行う", department: "revenue")
    updated = create_candidate(title: "LPテストで仮説検証を行う", department: "general")

    result = ActionCandidateDepartmentClassifierService.new(scope: ActionCandidate.where(id: [ kept.id, updated.id ])).call

    assert_equal "revenue", kept.reload.department
    assert_equal "lab", updated.reload.department
    assert_equal 1, result.updated_count
  end

  test "all mode overwrites existing department" do
    candidate = create_candidate(title: "LPテストで仮説検証を行う", department: "revenue")

    result = ActionCandidateDepartmentClassifierService.new(scope: ActionCandidate.where(id: candidate.id), overwrite: true).call

    assert_equal "lab", candidate.reload.department
    assert_equal 1, result.updated_count
  end

  private

  def build_candidate(attributes = {})
    ActionCandidate.new(
      {
        business: businesses(:suelog),
        title: "分類テスト",
        action_type: "other",
        department: "general",
        generation_source: "manual",
        immediate_value_yen: 1_000,
        success_probability: 0.5
      }.merge(attributes)
    )
  end

  def create_candidate(attributes = {})
    build_candidate(attributes).tap(&:save!)
  end
end
