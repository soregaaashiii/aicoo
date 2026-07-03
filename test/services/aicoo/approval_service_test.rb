require "test_helper"

module Aicoo
  class ApprovalServiceTest < ActiveSupport::TestCase
    test "approves action candidate and creates auto revision task and log" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "承認Service SEO改善",
        action_type: "seo_improvement",
        status: "pending",
        immediate_value_yen: 20_000,
        success_probability: 0.5
      )

      assert_difference("AutoRevisionTask.count", 1) do
        assert_difference("ApprovalLog.count", 1) do
          result = ApprovalService.approve(candidate, operator: "owner", source: "test")

          assert_match(/ActionCandidate/, result.message)
          assert_equal AutoRevisionTask.last, result.redirect_record
        end
      end

      assert_equal "approved", candidate.reload.status
      assert_equal candidate, ApprovalLog.last.approvable
      assert_equal "approved", ApprovalLog.last.common_new_status
      assert_equal AutoRevisionTask.last.id, ApprovalLog.last.metadata["auto_revision_task_id"]
    end

    test "approves lab candidate and creates visible business" do
      candidate = AicooLabExperimentCandidate.create!(
        title: "ApprovalService Lab Business",
        experiment_type: "lp",
        acquisition_channel: "seo",
        description: "LP検証候補"
      )

      assert_difference("Business.real_businesses.count", 1) do
        assert_difference("ApprovalLog.count", 1) do
          result = ApprovalService.approve(candidate, operator: "owner", source: "test")

          assert_equal "ApprovalService Lab Business", result.redirect_record.name
        end
      end

      assert_equal "approved", candidate.reload.status
      assert_equal candidate.business, ApprovalLog.last.business
      assert_equal "approved", ApprovalLog.last.common_new_status
    end

    test "approves serp ai suggestion into executable serp query" do
      business = businesses(:suelog)
      keyword = business.business_serp_keywords.create!(
        keyword: "梅田 喫煙 個室",
        source: "ai_suggested",
        status: "pending",
        priority_score: 81
      )

      assert_difference("SerpQuery.count", 1) do
        assert_difference("ApprovalLog.count", 1) do
          result = ApprovalService.approve(keyword, operator: "owner", source: "test")

          assert_equal "梅田 喫煙 個室", result.redirect_record.query
        end
      end

      query = business.serp_queries.find_by!(query: "梅田 喫煙 個室")
      assert query.enabled?
      assert_equal "active", query.status
      assert_equal "active", keyword.reload.status
      assert_equal query.id, keyword.metadata_json["serp_query_id"]
    end

    test "reject logs common rejected status" do
      candidate = action_candidates(:nagazakicho_article)

      assert_difference("ApprovalLog.count", 1) do
        ApprovalService.reject(candidate, operator: "owner", source: "test")
      end

      assert_equal "rejected", candidate.reload.status
      assert_equal "reject", ApprovalLog.last.action
      assert_equal "rejected", ApprovalLog.last.common_new_status
    end

    test "delete is non destructive and archives status records" do
      candidate = action_candidates(:nagazakicho_article)

      assert_difference("ApprovalLog.count", 1) do
        ApprovalService.delete(candidate, operator: "owner", source: "test")
      end

      assert_equal "archived", candidate.reload.status
      assert_equal "delete", ApprovalLog.last.action
      assert_equal "archived", ApprovalLog.last.common_new_status
      assert_equal "non_destructive", ApprovalLog.last.metadata["deletion_mode"]
    end
  end
end
