require "test_helper"

class Aicoo::Serp::AutoNewBusinessPublisherTest < ActiveSupport::TestCase
  test "auto adds serp new business candidate as visible business and public landing page" do
    source_business = businesses(:suelog)
    candidate = nil

    assert_difference("Business.real_businesses.count", 1) do
      assert_no_difference("ApprovalLog.count") do
        candidate = source_business.action_candidates.create!(
          title: "新規事業候補: 請求前チェックリスト",
          description: "SERPから請求前チェックリストの需要を見つけた。",
          action_type: "build_lp",
          department: "new_business",
          generation_source: "integrated_decision",
          status: "idea",
          immediate_value_yen: 80_000,
          success_probability: 0.3,
          expected_hours: 2,
          execution_prompt: "LP検証を行う。",
          metadata: {
            "candidate_kind" => "new_business",
            "business_name" => "請求前チェックリスト",
            "source_query" => "請求前 チェックリスト",
            "problem" => "請求前のミスを減らしたい",
            "target_customer" => "フリーランス",
            "offering" => "請求前チェックリストテンプレート",
            "revenue_model" => "テンプレート販売と月額チェック支援",
            "validation_method" => "LPを公開し、事前登録とテンプレート購入意向を確認する",
            "launch_asset_type" => "lp"
          }
        )
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "請求前チェックリスト", candidate.business.name
    assert_equal "exploring", candidate.business.status
    assert_not candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert_equal "active", candidate.business.resource_status
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_nil candidate.metadata.dig("auto_new_business_publication", "business_service_id")
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
    assert Business.real_businesses.where(id: candidate.business_id).exists?

    assert_no_difference -> { Business.real_businesses.count } do
      assert_no_difference -> { AicooLabLandingPage.publicly_available.count } do
        result = Aicoo::Serp::AutoNewBusinessPublisher.call(candidates: [ candidate ])
        assert_equal 0, result.business_created_count
        assert_equal 0, result.lp_published_count
        assert_equal 0, result.failed_count
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "請求前チェックリスト", candidate.business.name
    assert_equal "exploring", candidate.business.status
    assert_not candidate.business.launched?
    assert_equal "lp_validation", candidate.business.lifecycle_stage
    assert candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
  end

  test "auto creates saas spec draft when saas foundation is selected" do
    candidate = ActionCandidate.create!(
      title: "飲食店予約受付SaaS",
      description: "飲食店の予約受付を自動化する新規事業候補。",
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      status: "idea",
      immediate_value_yen: 80_000,
      success_probability: 0.3,
      expected_hours: 2,
      execution_prompt: "SaaS仕様を作る。",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "飲食店予約受付SaaS",
        "source_query" => "飲食店 予約 自動化",
        "problem" => "飲食店が営業時間中の電話予約に対応しきれない",
        "target_customer" => "飲食店の運営者・担当者",
        "offering" => "予約受付を自動化するSaaS",
        "revenue_model" => "月額利用料で収益化する",
        "validation_method" => "SaaS仕様書と登録導線で予約受付の相談数を確認する",
        "launch_asset_type" => "saas"
      }
    )

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "exploring", candidate.business.status
    assert_not candidate.business.aicoo_lab_landing_pages.publicly_available.exists?
    service = candidate.business.business_services.find_by!(deploy_target: "saas_spec_draft")
    assert_equal "planning", service.status
    assert_equal "saas_spec_draft", service.metadata["service_kind"]
    assert_equal "飲食店予約受付SaaS", service.metadata.dig("spec_draft", "business_name")
    assert_equal service.id, candidate.metadata.dig("auto_new_business_publication", "business_service_id")
    assert_equal "saas", candidate.metadata.dig("auto_new_business_publication", "created_asset_type")
  end

  test "does not auto publish query named low quality candidate" do
    assert_no_difference("Business.real_businesses.count") do
      candidate = ActionCandidate.create!(
        title: "飲食店 代行 大阪の検証事業",
        description: "検索クエリをそのまま候補名にしている。",
        action_type: "new_business",
        department: "new_business",
        generation_source: "serp",
        status: "idea",
        immediate_value_yen: 80_000,
        success_probability: 0.3,
        expected_hours: 2,
        metadata: {
          "candidate_kind" => "new_business",
          "business_name" => "飲食店 代行 大阪の検証事業",
          "source_query" => "飲食店 代行 大阪",
          "problem" => "飲食店が代行先を選べない",
          "target_customer" => "飲食店の運営者・担当者",
          "offering" => "飲食店向け代行支援",
          "revenue_model" => "月額支援で収益化する",
          "validation_method" => "LPで相談登録を確認する"
        }
      )

      candidate.reload
      assert_equal "planning", candidate.status
      assert_equal "needs_edit", candidate.metadata.dig("business_idea_quality", "status")
      assert_equal true, candidate.metadata["requires_human_edit"]
      assert_nil candidate.business_id
    end
  end

  test "repairer restores approved serp candidate without owner approval" do
    source_business = businesses(:suelog)
    candidate = source_business.action_candidates.create!(
      title: "一時候補",
      description: "後からSERP新規事業候補へ補正する",
      action_type: "other",
      department: "general",
      generation_source: "manual",
      status: "idea",
      immediate_value_yen: 50_000,
      success_probability: 0.2,
      expected_hours: 1
    )
    candidate.update_columns(
      action_type: "build_lp",
      department: "new_business",
      generation_source: "serp",
      status: "approved",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "SERP復旧検証支援サービス",
        "source_query" => "SERP 復旧 テスト",
        "target_customer" => "小規模事業者の運営者",
        "problem" => "SERPから見つけた市場の初期検証ができていない",
        "offering" => "市場検証支援サービス",
        "revenue_model" => "月額検証支援で収益化する",
        "validation_method" => "LPを公開し相談登録を確認する"
      }
    )

    assert_difference("Business.real_businesses.count", 1) do
      assert_no_difference("ApprovalLog.count") do
        result = Aicoo::ApprovedNewBusinessCandidateRepairer.call(source: "test_repair")
        assert_operator result.repaired_count, :>=, 1
        assert_equal 0, result.failed_count
      end
    end

    candidate.reload
    assert_equal "done", candidate.status
    assert_equal "SERP復旧検証支援サービス", candidate.business.name
    assert_equal "exploring", candidate.business.status
    assert Business.real_businesses.where(id: candidate.business_id).exists?
    assert_equal true, candidate.metadata.dig("auto_new_business_publication", "completed")
  end

  test "skips candidate when matching deleted serp business is blocked" do
    deleted_business = Business.create!(
      name: "削除済み重複候補",
      status: "exploring",
      source: "serp",
      metadata: { "discovery_fingerprint" => "duplicate-fingerprint" }
    )
    deleted_business.soft_delete!(reason: "SERP誤生成", actor: "owner", source: "test")
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "削除済み重複候補",
      description: "削除済み候補と同じ",
      action_type: "other",
      department: "general",
      generation_source: "manual",
      status: "idea",
      immediate_value_yen: 30_000,
      success_probability: 0.2
    )
    candidate.update_columns(
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "削除済み重複候補",
        "discovery_fingerprint" => "duplicate-fingerprint"
      }
    )

    assert_no_difference([ "Business.count", "AicooLabLandingPage.count" ]) do
      result = Aicoo::Serp::AutoNewBusinessPublisher.call(candidates: [ candidate ])
      assert_equal 1, result.skipped_count
      assert_equal 0, result.business_created_count
      assert_equal 0, result.lp_created_count
    end

    candidate.reload
    assert_equal true, candidate.metadata["do_not_recreate"]
    assert_equal true, candidate.metadata["auto_republish_blocked"]
    assert_equal deleted_business.id, candidate.metadata["deleted_business_id"]
  end

  test "landing page builder rejects deleted business" do
    business = Business.create!(name: "削除済みLP禁止", status: "exploring", source: "serp")
    candidate = ActionCandidate.create!(
      business: business,
      title: "削除済みLP禁止",
      description: "LPを作らない",
      action_type: "new_business",
      department: "new_business",
      generation_source: "serp",
      status: "done",
      immediate_value_yen: 30_000,
      success_probability: 0.2,
      metadata: {
        "candidate_kind" => "new_business",
        "business_name" => "削除済みLP禁止"
      }
    )
    business.soft_delete!(reason: "SERP誤生成", actor: "owner", source: "test")

    assert_no_difference("AicooLabLandingPage.count") do
      error = assert_raises(ArgumentError) do
        Aicoo::Owner::NewBusinessLandingPageBuilder.new(candidate).call
      end
      assert_match "削除済みBusiness", error.message
    end
  end
end
