require "test_helper"
require "rake"

class AicooSeoArticleExpectedValuesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:recalculate_seo_article_expected_values")
    Rake::Task["aicoo:recalculate_seo_article_expected_values"].reenable
  end

  test "recalculate task applies seo-only value and is idempotent" do
    candidate = ActionCandidate.create!(
      business: businesses(:suelog),
      title: "東通り 居酒屋 喫煙可の記事を作る",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      department: "revenue",
      status: "idea",
      immediate_value_yen: 1_260_634,
      success_probability: 0.5,
      expected_hours: 2,
      metadata: {
        "source_query" => "東通り 居酒屋 喫煙可",
        "impressions" => 10_000,
        "current_ctr" => 0.01,
        "target_ctr" => 0.03,
        "conversion_rate" => 0.02,
        "profit_per_conversion" => 1_000,
        "seo_expected_value_cap" => 100_000,
        "seo_article_value_model" => {
          "cap_yen" => 100_000
        }
      }
    )
    candidate.update_columns(
      expected_profit_yen: 1_260_634,
      expected_revenue_value_yen: 1_260_634,
      expected_total_value_yen: 1_260_634,
      final_expected_value_yen: 1_260_634,
      metadata: candidate.metadata.except("seo_article_value_model")
    )

    ENV["APPLY"] = "1"
    output, = capture_io do
      Rake::Task["aicoo:recalculate_seo_article_expected_values"].invoke
    end

    assert_includes output, "mode=apply"
    assert_includes output, "eligible="
    assert_includes output, "recalculated="
    assert_includes output, "previously_capped=1"
    assert_includes output, "cap_removed=1"
    assert_includes output, "actual="
    assert_includes output, "estimated="
    assert_includes output, "assumption_used="
    assert_includes output, "candidate_id=#{candidate.id} query=東通り 居酒屋 喫煙可"
    assert_equal 2_000, candidate.reload.final_expected_value_yen
    assert_equal 2_000, candidate.expected_total_value_yen
    assert_nil candidate.metadata["seo_expected_value_cap"]
    assert_nil candidate.metadata.dig("seo_article_value_model", "cap_yen")

    ENV.delete("APPLY")
    Rake::Task["aicoo:recalculate_seo_article_expected_values"].reenable
    second_output, = capture_io do
      Rake::Task["aicoo:recalculate_seo_article_expected_values"].invoke
    end

    assert_includes second_output, "mode=dry-run"
    assert_includes second_output, "recalculated=0"
    assert_includes second_output, "cap_removed=0"
  ensure
    ENV.delete("APPLY")
  end

  test "recalculate task recovers query and skips terminal duplicate candidates" do
    business = businesses(:suelog)
    business.business_serp_keywords.create!(
      keyword: "梅田 喫煙 カフェ",
      normalized_keyword: BusinessSerpKeyword.normalize("梅田 喫煙 カフェ"),
      source: "gsc",
      status: "active",
      latest_impressions: 8_000,
      latest_ctr: 0.01,
      latest_rank: 13,
      priority_score: 75
    )
    representative = ActionCandidate.create!(
      business:,
      title: "「梅田 喫煙 カフェ」向けの新規記事候補を作成する",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      department: "revenue",
      status: "proposal",
      success_probability: 0.36,
      expected_hours: 2,
      metadata: {
        "calculation_status" => "insufficient_data"
      }
    )
    duplicate = ActionCandidate.create!(
      business:,
      title: "「梅田 喫煙 カフェ」向けの新規記事候補を作成する",
      action_type: "new_article_candidate",
      generation_source: "business_analyzer",
      department: "revenue",
      status: "rejected_duplicate",
      success_probability: 0.36,
      expected_hours: 2,
      final_expected_value_yen: 0,
      metadata: {
        "duplicate_of_candidate_id" => representative.id,
        "calculation_status" => "insufficient_data"
      }
    )

    ENV["APPLY"] = "1"
    output, = capture_io do
      Rake::Task["aicoo:recalculate_seo_article_expected_values"].invoke
    end

    assert_includes output, "query_recovered="
    assert_includes output, "skipped_terminal_status="
    assert_includes output, "candidate_id=#{representative.id} query=梅田 喫煙 カフェ"
    assert representative.reload.final_expected_value_yen.positive?
    assert_equal "梅田 喫煙 カフェ", representative.metadata["source_query"]
    assert_equal "estimated", representative.metadata["calculation_status"]
    assert_equal "rejected_duplicate", duplicate.reload.status
    assert_equal 0, duplicate.final_expected_value_yen
  ensure
    ENV.delete("APPLY")
  end
end
