require "test_helper"
require "rake"

class AicooSuelogArticleExpectedValuesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("aicoo:recalculate_suelog_article_expected_values")
    Rake::Task["aicoo:recalculate_suelog_article_expected_values"].reenable
    ActionCandidate.update_all(status: "done")
    @business = businesses(:suelog)
    @business.update!(status: "launched", business_type: "seo_media", project_key: "suelog")
    @business.business_metric_dailies.delete_all
    @business.business_metric_dailies.create!(
      recorded_on: Date.current,
      clicks: 1_000,
      impressions: 20_000,
      sessions: 900,
      pageviews: 1_500,
      users: 700,
      phone_clicks: 30,
      map_clicks: 60,
      affiliate_clicks: 10,
      average_engagement_time_seconds: 80
    )
  end

  test "dry run recalculates suelog business analyzer article candidates without saving" do
    candidate = old_suelog_candidate!(
      title: "「東通り 居酒屋 喫煙可」向けの新規記事候補を作成する",
      generation_source: "business_analyzer",
      action_type: "new_article_candidate",
      metadata: {
        "source_query" => "東通り 居酒屋 喫煙可",
        "impressions" => 20_000,
        "clicks" => 120,
        "ctr" => 0.006,
        "position" => 12,
        "ga4_pageviews" => 2_000,
        "shop_clicks" => 300
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end

    assert_includes output, "mode=dry-run"
    assert_includes output, "eligible=1"
    assert_includes output, "recalculated=1"
    assert_includes output, "candidate_id=#{candidate.id}"
    assert_includes output, "value_model_name=suelog_article"
    assert_equal 39, candidate.reload.expected_profit_yen
    assert_nil candidate.metadata["seo_expected_value_skipped"]
  end

  test "apply saves suelog article value metadata and keeps generic seo model skipped" do
    candidate = old_suelog_candidate!(
      title: "「梅田 喫煙 カフェ」向けの新規記事候補を作成する",
      generation_source: "business_analyzer",
      action_type: "new_article_candidate",
      metadata: {
        "source_query" => "梅田 喫煙 カフェ",
        "impressions" => 5_000,
        "clicks" => 25,
        "ctr" => 0.005,
        "position" => 22,
        "ga4_pageviews" => 500,
        "shop_clicks" => 80
      }
    )

    ENV["APPLY"] = "1"
    output, = capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end

    candidate.reload
    assert_includes output, "mode=apply"
    assert_operator candidate.expected_profit_yen, :>, 39
    assert_equal candidate.expected_profit_yen, candidate.expected_revenue_value_yen
    assert_equal candidate.expected_profit_yen, candidate.expected_total_value_yen
    assert_equal candidate.expected_profit_yen, candidate.final_expected_value_yen
    assert_equal true, candidate.metadata["seo_expected_value_skipped"]
    assert_equal "suelog_generated", candidate.metadata["skip_reason"]
    assert_equal "suelog_article", candidate.metadata.dig("value_model", "name")
    assert candidate.metadata["gsc_inputs"].present?
    assert candidate.metadata["ga4_inputs"].present?
    assert candidate.metadata["shopclick_inputs"].present?
    assert candidate.metadata["business_metric_inputs"].present?
    assert candidate.metadata["calculation_reason"].present?
    assert_equal Aicoo::SuelogArticleExpectedValue::CALCULATION_VERSION, candidate.metadata.dig("value_model", "calculation_version")

    ENV.delete("APPLY")
    Rake::Task["aicoo:recalculate_suelog_article_expected_values"].reenable
    second_output, = capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end
    assert_includes second_output, "recalculated=0"
    assert_includes second_output, "unchanged=1"
  ensure
    ENV.delete("APPLY")
  end

  test "suelog db article candidates are eligible but normal business candidates are skipped" do
    suelog_candidate = old_suelog_candidate!(
      title: "「難波 喫煙 居酒屋」向けの記事を作成する",
      generation_source: "suelog_db",
      action_type: "article_create",
      metadata: {
        "query" => "難波 喫煙 居酒屋",
        "impressions" => 11_000,
        "clicks" => 55,
        "ctr" => 0.005,
        "position" => 18
      }
    )
    old_suelog_candidate!(
      business: businesses(:cards),
      title: "「名刺 SaaS 比較」向けの記事を作成する",
      generation_source: "business_analyzer",
      action_type: "new_article_candidate",
      metadata: {
        "source_query" => "名刺 SaaS 比較",
        "impressions" => 10_000,
        "clicks" => 100,
        "ctr" => 0.01,
        "position" => 10
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end

    assert_includes output, "eligible=1"
    assert_includes output, "skipped_non_suelog=1"
    assert_includes output, "candidate_id=#{suelog_candidate.id}"
  end

  test "terminal suelog article candidates are skipped" do
    old_suelog_candidate!(
      title: "「吸えログ 比較」向けの記事を作成する",
      generation_source: "business_analyzer",
      action_type: "new_article_candidate",
      status: "rejected_duplicate",
      metadata: {
        "source_query" => "吸えログ 比較",
        "impressions" => 10_000,
        "clicks" => 100,
        "ctr" => 0.01,
        "position" => 12
      }
    )

    output, = capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end

    assert_includes output, "eligible=0"
    assert_includes output, "skipped_terminal_status=1"
  end

  test "different inputs produce different recalculated suelog article values" do
    high = old_suelog_candidate!(
      title: "「東通り 居酒屋 喫煙可」向けの新規記事候補を作成する",
      metadata: {
        "source_query" => "東通り 居酒屋 喫煙可",
        "impressions" => 20_000,
        "clicks" => 120,
        "ctr" => 0.006,
        "position" => 12
      }
    )
    low = old_suelog_candidate!(
      title: "「梅田 喫煙 カフェ」向けの新規記事候補を作成する",
      metadata: {
        "source_query" => "梅田 喫煙 カフェ",
        "impressions" => 5_000,
        "clicks" => 25,
        "ctr" => 0.005,
        "position" => 22
      }
    )

    ENV["APPLY"] = "1"
    capture_io do
      Rake::Task["aicoo:recalculate_suelog_article_expected_values"].invoke
    end

    assert_not_equal high.reload.expected_profit_yen, low.reload.expected_profit_yen
  ensure
    ENV.delete("APPLY")
  end

  private

  def old_suelog_candidate!(business: @business, title:, generation_source: "business_analyzer", action_type: "new_article_candidate", status: "proposal", metadata:)
    candidate = ActionCandidate.create!(
      business:,
      title:,
      action_type:,
      generation_source:,
      department: "revenue",
      status:,
      immediate_value_yen: 39,
      success_probability: 0.36,
      expected_hours: 2,
      metadata:
    )
    candidate.update_columns(
      immediate_value_yen: 39,
      expected_profit_yen: 39,
      expected_revenue_value_yen: 39,
      expected_total_value_yen: 39,
      final_expected_value_yen: 39,
      metadata: metadata.deep_stringify_keys,
      updated_at: Time.current
    )
    candidate
  end
end
