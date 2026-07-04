require "test_helper"

module Aicoo
  module Owner
    class NewBusinessPipelineBoardTest < ActiveSupport::TestCase
      test "returns businessization next action for pending new business candidate" do
        candidate = ActionCandidate.create!(
          business: businesses(:suelog),
          title: "喫煙可能会議室検索",
          description: "喫煙できる会議室を探したい人向け。",
          action_type: "new_business",
          department: "new_business",
          generation_source: "integrated_decision",
          status: "idea",
          immediate_value_yen: 40_000,
          expected_hours: 2,
          success_probability: 0.4,
          metadata: { "candidate_kind" => "new_business" }
        )

        result = NewBusinessPipelineBoard.new(selected_id: candidate.id).call

        assert_equal "候補", result.selected.current_state
        assert_equal 10, result.selected.progress_percent
        assert_equal "Owner承認待ち", result.selected.stuck_reason
        assert_equal "Business化する", result.selected.next_action_label
        assert_match %r{/owner/new_business_pipeline/action_candidates/#{candidate.id}/approve}, result.selected.next_action_path
      end
    end
  end
end
