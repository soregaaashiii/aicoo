require "test_helper"

class ApprovalLogTest < ActiveSupport::TestCase
  test "validates approval action and common status" do
    log = ApprovalLog.new(
      approvable: action_candidates(:nagazakicho_article),
      business: businesses(:suelog),
      action: "approve",
      operator: "owner",
      source: "test",
      previous_status: "idea",
      new_status: "approved",
      common_previous_status: "pending",
      common_new_status: "approved",
      message: "承認しました",
      approved_at: Time.current
    )

    assert log.valid?

    log.action = "unknown"
    assert_not log.valid?
  end
end
