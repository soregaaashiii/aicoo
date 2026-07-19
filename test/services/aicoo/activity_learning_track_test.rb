require "test_helper"

module Aicoo
  class ActivityLearningTrackTest < ActiveSupport::TestCase
    test "uses action candidate track only for an explicit candidate id" do
      candidate = action_candidates(:nagazakicho_article)
      evaluation = create_evaluation(metadata: { "action_candidate_id" => candidate.id })

      track = ActivityLearningTrack.call(evaluation)

      assert_equal "action_candidate", track.name
      assert_equal candidate, track.action_candidate
      assert_equal "explicit_candidate_id", track.link_source
    end

    test "uses independent track when only a resource id is shared" do
      candidate = action_candidates(:nagazakicho_article)
      candidate.update!(metadata: { "article_id" => "same-article" })
      evaluation = create_evaluation(resource_id: "same-article")

      track = ActivityLearningTrack.call(evaluation)

      assert_equal "independent_activity", track.name
      assert_nil track.action_candidate
    end

    private

    def create_evaluation(metadata: {}, resource_id: "article-1")
      business = businesses(:suelog)
      activity = BusinessActivityLog.create!(
        business:,
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id:,
        title: "記事更新",
        occurred_at: 10.days.ago,
        detected_at: 10.days.ago,
        idempotency_key: "learning-track-#{resource_id}-#{SecureRandom.hex(4)}",
        metadata:
      )
      ActivityEvaluation.create!(
        business:,
        business_activity_log: activity,
        evaluation_window_days: 7,
        status: "evaluated",
        evaluated_at: Time.current
      )
    end
  end
end
