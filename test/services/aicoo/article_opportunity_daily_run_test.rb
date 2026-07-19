require "test_helper"
require "ostruct"

module Aicoo
  class ArticleOpportunityDailyRunTest < ActiveSupport::TestCase
    SnapshotResult = Struct.new(
      :snapshot_count,
      :snapshot_ids,
      :failed_count,
      :published_article_count,
      :created_count,
      :updated_count,
      :unavailable_counts,
      keyword_init: true
    )

    test "target business creates production candidates idempotently for the same snapshot" do
      business = businesses(:suelog)
      daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "manual")
      snapshot_result = SnapshotResult.new(
        snapshot_count: 1,
        snapshot_ids: [ 123 ],
        failed_count: 0,
        published_article_count: 1,
        created_count: 1,
        updated_count: 0,
        unavailable_counts: {}
      )
      analyzer_result = analyzer_result_for(snapshot_id: 123)
      today_result = OpenStruct.new(
        activated_count: 1,
        duplicate_suppressed_count: 0,
        today_eligible_count: 1,
        latest_snapshot_at: Time.current
      )

      with_article_opportunity_stubs(snapshot_result:, analyzer_result:, today_result:) do
        first = Aicoo::ArticleOpportunityDailyRun.call(daily_run:, business:)
        second = Aicoo::ArticleOpportunityDailyRun.call(daily_run:, business:)

        assert_equal 1, first.candidate_created_count
        assert_equal 0, first.candidate_updated_count
        assert_equal 0, second.candidate_created_count
        assert_equal 1, second.candidate_updated_count
      end

      candidates = business.action_candidates.where("metadata ->> 'value_model_name' = ?", Aicoo::ArticleOpportunityDailyRun::MODEL_NAME)
      assert_equal 1, candidates.count
      assert_equal "123", candidates.first.metadata["snapshot_id"].to_s
      assert_equal "ctr_improvement", candidates.first.metadata["opportunity_type"]
    end

    test "non target business is skipped" do
      business = Business.create!(name: "別事業", description: "Not Suelog", status: "launched", business_type: "saas")
      daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "manual")

      Aicoo::Suelog::SiteInsightsAdapter.stub(:target?, false) do
        result = Aicoo::ArticleOpportunityDailyRun.call(daily_run:, business:)

        assert_equal "skipped", result.status
        assert_equal 0, result.candidate_created_count
      end
    end

    test "article opportunity analysis step is recoverable" do
      assert_includes AicooDailyRunStep::RECOVERABLE_STEP_NAMES, Aicoo::ArticleOpportunityDailyRun::STEP_NAME
    end

    private

    def analyzer_result_for(snapshot_id:)
      draft = Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner::CandidateDraft.new(
        "お初天神デート記事のCTR改善を行う",
        "article_update",
        "/articles/ohatsutenjin-date のArticleAnalyticsSnapshotから CTR改善 Opportunity を検出しました。",
        "タイトルとmeta descriptionを見直す",
        {
          "value_model_name" => Aicoo::ArticleOpportunityDailyRun::MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => snapshot_id,
          "article_id" => 10,
          "article_path" => "/articles/ohatsutenjin-date",
          "opportunity_type" => "ctr_improvement",
          "opportunity_label" => "CTR改善",
          "expected_improvement_score" => 12.3,
          "search_demand_score" => 8.0,
          "improvement_potential_score" => 7.0,
          "success_probability" => 0.6,
          "estimated_work_hours" => 0.5,
          "business_value" => 1.2,
          "ranking_reason" => "表示上位でCTR改善余地があります。"
        }
      )
      article_result = OpenStruct.new(candidate_drafts: [ draft ])
      OpenStruct.new(
        article_results: [ article_result ],
        failed_count: 0,
        analyzed_count: 1,
        article_count: 1
      )
    end

    def with_article_opportunity_stubs(snapshot_result:, analyzer_result:, today_result:)
      analyzer_runner = OpenStruct.new(call: analyzer_result)
      today_connector = OpenStruct.new(call: today_result)
      Aicoo::ArticleAnalyticsSnapshotBuilder.stub(:call, snapshot_result) do
        Aicoo::ArticleOpportunityAnalyzer::SnapshotRunner.stub(:new, analyzer_runner) do
          Aicoo::ArticleOpportunityTodayConnector.stub(:new, today_connector) do
            yield
          end
        end
      end
    end
  end
end
