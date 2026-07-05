require "test_helper"

module Owner
  class NewBusinessPipelinesControllerTest < ActionDispatch::IntegrationTest
    test "shows new business pipeline page" do
      get owner_new_business_pipeline_url

      assert_response :success
      assert_includes response.body, "新規事業作成"
      assert_includes response.body, "新規事業候補"
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
            "business_name" => "喫煙可能コワーキング検索",
            "problem" => "喫煙できる作業場所が探しにくい",
            "target_customer" => "外出先で作業したい喫煙者",
            "revenue_model" => "送客・広告"
          }
        )
      end

      candidate.reload
      created_business = Business.find(candidate.business_id)
      assert_equal "done", candidate.status
      assert_equal "喫煙可能コワーキング検索", created_business.name
      assert_includes Business.real_businesses.pluck(:id), created_business.id
      assert created_business.aicoo_lab_landing_pages.publicly_available.exists?

      assert_no_difference("Business.count") do
        patch approve_owner_new_business_pipeline_candidate_url(candidate)
      end
      assert_redirected_to owner_new_business_pipeline_url(selected_id: candidate.id, anchor: "selected-candidate")
    end

    test "new business candidate automatically creates and publishes landing page" do
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
          "business_name" => "喫煙可能個室検索",
          "problem" => "喫煙できる個室が探しにくい",
          "target_customer" => "個室で会食したい喫煙者",
          "revenue_model" => "送客・広告"
        }
      )

      candidate.reload
      landing_page = candidate.business.aicoo_lab_landing_pages.publicly_available.first
      assert landing_page
      assert_equal candidate.business, landing_page.business
      assert landing_page.publicly_visible?
    end
  end
end
