require "test_helper"

module Aicoo
  module Owner
    class NewBusinessPipelineBoardTest < ActiveSupport::TestCase
      test "returns auto published new business candidate as validation item" do
        candidate = nil
        assert_difference("Business.count", 1) do
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
        end

        result = NewBusinessPipelineBoard.new(selected_id: candidate.id).call

        assert_equal "done", candidate.reload.status
        assert result.selected.business
        assert result.selected.landing_page
        assert_equal "検証中", result.selected.current_state
        assert_equal 75, result.selected.progress_percent
        assert_equal "計測待ち", result.selected.stuck_reason
        assert_equal "検証結果待ち", result.selected.next_action_label
        assert_nil result.selected.next_action_path
      end
    end
  end
end
