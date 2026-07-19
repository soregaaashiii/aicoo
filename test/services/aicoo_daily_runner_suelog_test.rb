require "test_helper"
require "ostruct"

class AicooDailyRunnerSuelogTest < ActiveSupport::TestCase
  test "suelog database steps skip safely when database url is missing" do
    business = businesses(:suelog)
    business.update!(project_key: "suelog", repository_name: "suelog")
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "test")
    runner = AicooDailyRunner.new(target_date: Date.yesterday, source: "test")

    without_suelog_database_url do
      assert_nothing_raised do
        runner.send(:run_suelog_database_steps!, daily_run)
      end
    end

    step = daily_run.aicoo_daily_run_steps.find_by!(step_name: "suelog_database_health_check")
    assert_equal "skipped", step.status
    assert_equal "missing_database_url", step.metadata["reason"]
  end

  test "suelog candidate generation records legacy article analyzer routing metadata" do
    business = businesses(:suelog)
    business.update!(project_key: "suelog", repository_name: "suelog")
    daily_run = AicooDailyRun.create!(target_date: Date.yesterday, status: "running", source: "test")
    runner = AicooDailyRunner.new(target_date: Date.yesterday, source: "test")
    health = OpenStruct.new(
      success?: true,
      diagnostics: { "shops_count" => 1, "articles_count" => 1, "shop_clicks_count" => 1 },
      shops_count: 1,
      articles_count: 1,
      shop_clicks_count: 1
    )
    result = Aicoo::CandidateGenerators::SuelogGenerator::Result.new(
      created: [],
      skipped: [ "legacy_article_analyzer_skipped:new_analyzer_active" ],
      health:
    )

    Aicoo::ExternalSources::SuelogHealthCheck.stub(:call, health) do
      Aicoo::CandidateGenerators::SuelogGenerator.stub(:call, result) do
        runner.send(:run_suelog_database_steps!, daily_run)
      end
    end

    step = daily_run.aicoo_daily_run_steps.find_by!(step_name: "suelog_candidate_generation")
    assert_equal "success", step.status
    assert_equal true, step.metadata["legacy_article_analyzer_skipped"]
    assert_equal "new_analyzer_active", step.metadata["legacy_article_analyzer_skip_reason"]
    assert_equal Aicoo::ArticleOpportunityDailyRun::MODEL_NAME, step.metadata["active_article_analyzer"]
  end

  private

  def without_suelog_database_url
    original = ENV["SUELOG_DATABASE_URL"]
    ENV.delete("SUELOG_DATABASE_URL")
    yield
  ensure
    ENV["SUELOG_DATABASE_URL"] = original if original
  end
end
