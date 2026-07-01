require "test_helper"

class Aicoo::ExternalCommitImporterTest < ActiveSupport::TestCase
  test "imports external commit into action result activity and execution log" do
    candidate = action_candidates(:nagazakicho_article)
    business = businesses(:suelog)

    assert_difference("ActionExecutionLog.count", 1) do
      assert_difference("ActionResult.count", 1) do
        assert_difference(-> { BusinessActivityLog.where(activity_type: "code_revision_imported").count }, 1) do
          result = Aicoo::ExternalCommitImporter.new(
            business_id: business.id,
            action_candidate_id: candidate.id,
            repository: "soregaaashiii/suelog",
            commit_sha: "bcc4a2c",
            changed_files: "app/views/shops/show.html.erb\napp/views/shared/_shop_cards.html.erb",
            result_summary: "CV導線を改善しました。",
            test_result: "git diff --check OK",
            executed_at: "2026-07-01T12:00"
          ).call

          assert_equal candidate, result.action_result.action_candidate
          assert_equal business, result.business_activity_log.business
          assert_equal "bcc4a2c", result.action_execution_log.metadata["commit_sha"]
          assert_equal "code_revision_imported", result.business_activity_log.activity_type
        end
      end
    end

    assert_equal "done", candidate.reload.status
  end

  test "does not duplicate activity or execution log for same commit" do
    candidate = action_candidates(:nagazakicho_article)
    business = businesses(:suelog)
    params = {
      business_id: business.id,
      action_candidate_id: candidate.id,
      repository: "soregaaashiii/suelog",
      commit_sha: "bcc4a2c",
      changed_files: "app/views/shops/show.html.erb",
      result_summary: "CV導線を改善しました。"
    }

    Aicoo::ExternalCommitImporter.new(params).call

    assert_no_difference("ActionExecutionLog.count") do
      assert_no_difference("ActionResult.count") do
        assert_no_difference(-> { BusinessActivityLog.where(activity_type: "code_revision_imported").count }) do
          Aicoo::ExternalCommitImporter.new(params).call
        end
      end
    end
  end

  test "rejects action candidate from another business" do
    error = assert_raises(ArgumentError) do
      Aicoo::ExternalCommitImporter.new(
        business_id: businesses(:suelog).id,
        action_candidate_id: action_candidates(:ui_improvement).id,
        commit_sha: "abc123"
      ).call
    end

    assert_match(/属していません/, error.message)
  end
end
