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
        "profit_per_conversion" => 1_000
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
    assert_includes output, "recalculated=1"
    assert_equal 2_000, candidate.reload.final_expected_value_yen
    assert_equal 2_000, candidate.expected_total_value_yen

    ENV.delete("APPLY")
    Rake::Task["aicoo:recalculate_seo_article_expected_values"].reenable
    second_output, = capture_io do
      Rake::Task["aicoo:recalculate_seo_article_expected_values"].invoke
    end

    assert_includes second_output, "mode=dry-run"
    assert_includes second_output, "recalculated=0"
  ensure
    ENV.delete("APPLY")
  end
end
