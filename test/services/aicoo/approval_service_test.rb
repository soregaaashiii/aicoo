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
        assert_difference("AicooExecutorTask.count", 1) do
          assert_difference("ApprovalLog.count", 1) do
            result = ApprovalService.approve(candidate, operator: "owner", source: "test")

            assert_match(/ActionCandidate/, result.message)
            assert_equal AutoRevisionTask.last, result.redirect_record
          end
        end
      end

      assert_equal "approved", candidate.reload.status
      assert_equal "ready_for_codex", AutoRevisionTask.last.status
      assert_equal "approved", AicooExecutorTask.last.status
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

    test "repairs already approved new business action candidate into visible business" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "SERP由来の承認済み新規事業",
        description: "承認済みだがBusiness化前の候補",
        action_type: "new_business",
        generation_source: "serp",
        department: "new_business",
        status: "approved",
        approved_at: 1.day.ago,
        approved_by: "owner",
        metadata: {
          "candidate_kind" => "new_business",
          "business_name" => "SERP承認済み復旧Business"
        },
        immediate_value_yen: 30_000,
        success_probability: 0.4
      )

      assert_no_difference("Business.real_businesses.count") do
        result = ApprovalService.approve(candidate, operator: "owner", source: "test")

        assert_match(/既存Businessに紐付けました/, result.message)
      end

      business = Business.real_businesses.find_by!(name: "SERP承認済み復旧Business")
      assert_equal business, candidate.reload.business
      assert_equal business.id, candidate.metadata.dig("business_promotion", "business_id")
    end

    test "approves serp new business candidate directly into business without auto revision queue" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "SERPから見つけた請求チェック事業",
        description: "フリーランス向け請求前チェック",
        action_type: "new_business",
        generation_source: "serp",
        department: "new_business",
        status: "idea",
        metadata: {
          "candidate_kind" => "new_business",
          "business_name" => "請求前チェックリスト",
          "source_query" => "フリーランス 請求 チェック"
        },
        immediate_value_yen: 40_000,
        success_probability: 0.5
      )

      assert_no_difference("Business.real_businesses.count") do
        assert_no_difference("AutoRevisionTask.count") do
          result = ApprovalService.approve(candidate, operator: "owner", source: "test")

          assert_equal "請求前チェックリスト", result.redirect_record.name
          assert_match(/既存Businessに紐付けました/, result.message)
        end
      end

      business = Business.real_businesses.find_by!(name: "請求前チェックリスト")
      assert_equal "done", candidate.reload.status
      assert_equal business, candidate.business
      assert_equal "serp", business.source
      assert_equal "automatic", business.auto_revision_mode
      assert_equal "approval", business.auto_deploy_mode
      assert business.auto_build_enabled?
      assert_not business.auto_build_requires_approval?
      assert business.business_execution_profile.codex_enabled?
      assert business.business_execution_profile.codex_auto_submit_enabled?
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

    test "approves serp landing page candidate into draft landing page" do
      candidate = SerpLandingPageCandidate.create!(
        keyword: "梅田 喫煙 カフェ",
        service_name: "梅田 喫煙 カフェ ガイド",
        target_audience: "梅田で喫煙できるカフェを探す人",
        problem: "喫煙可否が分かりにくい。",
        lp_title: "梅田で喫煙できるカフェを探す",
        lp_description: "梅田の喫煙可能なカフェ選びを短時間で整理します。",
        cta_text: "店舗リストを見る",
        expected_value_score: 72
      )

      assert_difference("AicooLabLandingPage.count", 1) do
        assert_difference("ApprovalLog.count", 1) do
          result = ApprovalService.approve(candidate, operator: "owner", source: "test")

          assert_equal AicooLabLandingPage.last, result.redirect_record
        end
      end

      assert_equal "converted", candidate.reload.status
      assert_equal "draft", candidate.aicoo_lab_landing_page.public_status
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
