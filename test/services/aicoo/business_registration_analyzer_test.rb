require "test_helper"

class Aicoo::BusinessRegistrationAnalyzerTest < ActiveSupport::TestCase
  FakeInspector = Struct.new(:evidence) do
    def call
      evidence
    end
  end

  FakeClient = Struct.new(:payload) do
    def create_json(**)
      { parsed: payload, raw_response: "{}", model: "test-model" }
    end
  end

  test "persists ai analysis without querying other business data" do
    business = Business.create!(
      name: "Invoice AI",
      description: "請求書処理のプロトタイプ",
      status: "building",
      lifecycle_stage: "mvp",
      source: "business_registration_v2",
      metadata: {
        "business_registration_v2" => { "mode" => "prototype" },
        "business_profile" => {},
        "kpis" => [],
        "recommended_data_sources" => []
      }
    )
    prototype = business.business_prototypes.create!(
      prototype_type: "github",
      location: "https://github.com/example/invoice-ai",
      analysis_status: "queued"
    )
    candidate = business.action_candidates.create!(
      title: "初期解析",
      action_type: "data_preparation",
      status: "proposal",
      generation_source: "business_registration",
      metadata: { "initial_candidate" => true }
    )
    payload = {
      "business_type" => "saas",
      "revenue_model" => "月額課金",
      "customer" => "経理担当者",
      "development_status" => "private beta",
      "completion_percentage" => 65,
      "summary" => "請求書処理を自動化するSaaS",
      "kpis" => [ "処理件数", "継続率" ],
      "recommended_data_sources" => [ "github", "ga4" ],
      "today_action" => {
        "title" => "ベータ公開に必要な項目を特定する",
        "description" => "READMEと構成から不足項目を整理する。"
      }
    }

    Aicoo::BusinessRegistrationAnalyzer.new(
      business:,
      prototype:,
      client: FakeClient.new(payload),
      inspector: FakeInspector.new({ "technology_signals" => [ "rails" ] })
    ).call

    business.reload
    prototype.reload
    candidate.reload
    assert_equal "saas", business.business_type
    assert_equal "月額課金", business.metadata.dig("business_profile", "revenue_model")
    assert_equal [ "処理件数", "継続率" ], business.metadata["kpis"]
    assert_equal "succeeded", prototype.analysis_status
    assert_equal 65, prototype.analysis["completion_percentage"]
    assert_equal [ "rails" ], prototype.analysis["technology_stack"]
    assert_equal "ベータ公開に必要な項目を特定する", candidate.title
    assert business.business_data_source_settings.exists?(source_key: "github")
  end
end
