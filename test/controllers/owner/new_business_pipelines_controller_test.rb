require "test_helper"

module Owner
  class NewBusinessPipelinesControllerTest < ActionDispatch::IntegrationTest
    test "shows new business pipeline page" do
      get owner_new_business_pipeline_url

      assert_response :success
      assert_includes response.body, "新規事業作成"
      assert_includes response.body, "新規事業候補"
    end

    test "show does not auto publish candidates as a side effect" do
      publisher = ->(**) { raise "AutoNewBusinessPublisher must not run from new_business_pipeline#show" }

      Aicoo::Serp::AutoNewBusinessPublisher.stub(:call, publisher) do
        assert_no_difference([ "Business.count", "AicooLabLandingPage.count", "ActionCandidate.count" ]) do
          get owner_new_business_pipeline_url
        end
      end

      assert_response :success
    end

    test "new business candidate automatically creates business and makes it listable" do
      candidate = nil

      assert_difference("Business.count", 1) do
        candidate = ActionCandidate.create!(
          business: businesses(:suelog),
          title: "喫煙可能コワーキング検索",
          description: "喫煙できる作業場所を探したい人向けの新規事業候補。",
          action_type: "new_business",
          department: "new_business",
          generation_source: "serp",
          status: "idea",
          immediate_value_yen: 50_000,
          expected_hours: 2,
          success_probability: 0.4,
          metadata: {
            "candidate_kind" => "new_business",
            "business_name" => "喫煙可能コワーキング検索サービス",
            "problem" => "喫煙できる作業場所が探しにくい",
            "target_customer" => "外出先で作業したい喫煙者",
            "offering" => "喫煙可能なコワーキングを検索できるサービス",
            "revenue_model" => "送客・広告で収益化する",
            "validation_method" => "LPを公開して事前登録と検索導線のクリックを確認する",
            "launch_asset_type" => "lp"
          }
        )
      end

      candidate.reload
      created_business = Business.find(candidate.business_id)
      assert_equal "done", candidate.status
      assert_equal "喫煙可能コワーキング検索サービス", created_business.name
      assert_includes Business.real_businesses.pluck(:id), created_business.id
      assert_not created_business.auto_build_enabled?
      assert_not created_business.new_lp_auto_deploy_enabled?
      landing_page = created_business.aicoo_lab_landing_pages.first
      assert landing_page
      assert_equal "draft", landing_page.public_status
      assert_not landing_page.publicly_visible?

      assert_no_difference("Business.count") do
        patch approve_owner_new_business_pipeline_candidate_url(candidate)
      end
      assert_redirected_to owner_new_business_pipeline_url(selected_id: candidate.id, anchor: "selected-candidate")
    end

    test "new business candidate automatically creates draft landing page" do
      candidate = ActionCandidate.create!(
        business: businesses(:suelog),
        title: "喫煙可能個室検索",
        description: "喫煙できる個室を探したい人向けの新規事業候補。",
        action_type: "new_business",
        department: "new_business",
        generation_source: "serp",
        status: "idea",
        immediate_value_yen: 50_000,
        expected_hours: 2,
        success_probability: 0.4,
        metadata: {
          "candidate_kind" => "new_business",
          "business_name" => "喫煙可能個室検索サービス",
          "problem" => "喫煙できる個室が探しにくい",
          "target_customer" => "個室で会食したい喫煙者",
          "offering" => "喫煙可能な個室を検索できるサービス",
          "revenue_model" => "送客・広告で収益化する",
          "validation_method" => "LPを公開して事前登録とCTAクリックを確認する",
          "launch_asset_type" => "lp"
        }
      )

      candidate.reload
      landing_page = candidate.business.aicoo_lab_landing_pages.first
      assert landing_page
      assert_equal candidate.business, landing_page.business
      assert_equal "draft", landing_page.public_status
      assert_not landing_page.publicly_visible?
    end

    test "low quality candidate stays editable and can be approved after edit" do
      candidate = ActionCandidate.create!(
        title: "飲食店 代行 大阪の検証事業",
        description: "検索語をそのまま候補名にしている。",
        action_type: "new_business",
        department: "new_business",
        generation_source: "serp",
        status: "idea",
        immediate_value_yen: 50_000,
        expected_hours: 2,
        success_probability: 0.4,
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
      assert_nil candidate.business_id
      assert_equal "needs_edit", candidate.metadata.dig("business_idea_quality", "status")

      get owner_new_business_pipeline_url(selected_id: candidate.id)
      assert_response :success
      assert_includes response.body, "飲食店 代行 大阪の検証事業"
      assert_includes response.body, "候補を編集"
      assert_includes response.body, "要編集の候補"

      patch update_owner_new_business_pipeline_candidate_url(candidate), params: {
        action_candidate: {
          business_name: "飲食店SNS運用代行サービス",
          target_customer: "大阪の飲食店の運営者・担当者",
          problem: "SNS集客を継続できず予約機会を逃している",
          offering: "SNS投稿と予約導線の初期運用代行",
          value_proposition: "飲食店に絞って投稿作成から予約導線まで代行する",
          revenue_model: "初期相談と月額運用代行で収益化する",
          validation_method: "LPを公開し、相談登録とCTAクリックを7日で確認する",
          market: "飲食店向けSNS運用市場",
          market_category: "飲食店/SNS集客",
          region: "大阪",
          launch_asset_type: "saas"
        }
      }
      assert_redirected_to owner_new_business_pipeline_url(selected_id: candidate.id, anchor: "selected-candidate")
      assert_equal "auto_publishable", candidate.reload.metadata.dig("business_idea_quality", "status")

      assert_difference("Business.real_businesses.count", 1) do
        patch approve_owner_new_business_pipeline_candidate_url(candidate)
      end
      candidate.reload
      assert_equal "done", candidate.status
      assert_equal "飲食店SNS運用代行サービス", candidate.business.name
      assert candidate.business.business_services.where(deploy_target: "saas_spec_draft").exists?

      get owner_new_business_pipeline_url(tab: "businessized", selected_id: candidate.id)
      assert_response :success
      assert_includes response.body, "事業化済み"
      assert_includes response.body, "飲食店SNS運用代行サービス"
    end
  end
end
