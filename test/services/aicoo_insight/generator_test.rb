require "test_helper"

module AicooInsight
  class GeneratorTest < ActiveSupport::TestCase
    test "generates ctr improvement candidate from gsc data" do
      business = create_business("CTR insight")
      create_gsc_snapshot(business, rows: [
        { "query" => "梅田 喫煙 カフェ", "impressions" => 200, "clicks" => 1, "ctr" => 0.005, "position" => 3 }
      ])

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.title.include?("CTR改善") }
      assert candidate
      assert_equal "seo_improvement", candidate.action_type
      assert_equal "ai_insight", candidate.generation_source
      assert_includes candidate.evaluation_reason, "CTR改善"
    end

    test "generates position improvement candidate from gsc data" do
      business = create_business("Position insight")
      create_gsc_snapshot(business, rows: [
        { "query" => "難波 喫煙 居酒屋", "impressions" => 80, "clicks" => 3, "position" => 12 }
      ])

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.title.include?("順位改善") }
      assert candidate
      assert_equal "seo_improvement", candidate.action_type
      assert_includes candidate.execution_prompt, "内部リンク"
    end

    test "generates revenue improvement candidate when pageviews are high and profit is low" do
      business = create_business("Revenue insight")
      business.business_metric_dailies.create!(recorded_on: Date.current, pageviews: 400)

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.action_type == "sales" }
      assert candidate
      assert_includes candidate.evaluation_reason, "収益改善"
      assert_operator candidate.expected_profit_yen, :>, 0
    end

    test "generates neglect alert candidate from neglect loss" do
      business = create_business("Neglect insight")
      business.action_candidates.create!(
        title: "重要記事を更新する",
        action_type: "seo_improvement",
        generation_source: "manual",
        neglect_loss_90d_yen: 8_000,
        success_probability: 0.5
      )

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.title.include?("放置損失対策") }
      assert candidate
      assert_equal 8_000, candidate.neglect_loss_90d_yen
      assert_includes candidate.evaluation_reason, "放置アラート"
    end

    test "generates growth expansion candidate from rising metrics" do
      business = create_business("Growth insight")
      business.business_metric_dailies.create!(recorded_on: 10.days.ago.to_date, clicks: 2, pageviews: 5)
      business.business_metric_dailies.create!(recorded_on: Date.current, clicks: 20, pageviews: 40)

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.action_type == "seo_article" }
      assert candidate
      assert_includes candidate.evaluation_reason, "成長記事拡張"
    end

    test "generates withdrawal candidate for long running low response business" do
      business = create_business("Withdraw insight")
      14.times do |index|
        business.business_metric_dailies.create!(recorded_on: index.days.ago.to_date)
      end

      result = Generator.new(business:).call

      candidate = result.created.find { |action| action.action_type == "withdraw" }
      assert candidate
      assert_includes candidate.evaluation_reason, "撤退候補"
    end

    test "does not create duplicates within thirty days" do
      business = create_business("Duplicate insight")
      create_gsc_snapshot(business, rows: [
        { "query" => "心斎橋 喫煙", "impressions" => 200, "clicks" => 1, "ctr" => 0.005, "position" => 2 }
      ])

      assert_difference("ActionCandidate.where(generation_source: 'ai_insight').count", 1) do
        Generator.new(business:).call
      end

      assert_no_difference("ActionCandidate.where(generation_source: 'ai_insight').count") do
        Generator.new(business:).call
      end
    end

    test "generated insight candidate is included in revenue ranking" do
      business = create_business("Revenue linkage insight")
      create_gsc_snapshot(business, rows: [
        { "query" => "梅田 喫煙 バー", "impressions" => 240, "clicks" => 1, "ctr" => 0.004, "position" => 4 }
      ])

      result = Generator.new(business:).call
      candidate = result.created.first
      ranking = AicooRevenue::RankingBuilder.new(available_minutes: 300, available_budget_yen: 0, source: "action_candidate").call

      assert_includes ranking.revenue_rankings.map(&:source_id), candidate.id
    end

    test "generate all with source records successful generation run" do
      business = create_business("Run success insight")
      create_gsc_snapshot(business, rows: [
        { "query" => "京橋 喫煙", "impressions" => 240, "clicks" => 1, "ctr" => 0.004, "position" => 4 }
      ])

      result = Generator.generate_all!(source: "manual")
      run = AicooInsightGenerationRun.last

      assert_equal 1, result.created_count
      assert_equal "manual", run.source
      assert_equal "success", run.status
      assert_equal 1, run.generated_count
      assert_equal 0, run.skipped_count
      assert run.finished_at
    end

    test "generate all with source records failed generation run" do
      with_singleton_stub(Generator, :generate_all_without_run!, -> { raise RuntimeError, "insight boom" }) do
        assert_raises(RuntimeError) do
          Generator.generate_all!(source: "daily_run")
        end
      end

      run = AicooInsightGenerationRun.last
      assert_equal "daily_run", run.source
      assert_equal "failed", run.status
      assert_match "RuntimeError: insight boom", run.error_message
    end

    private

    def create_business(name)
      Business.create!(name:)
    end

    def create_gsc_snapshot(business, rows:)
      AicooDataSnapshot.create!(
        source_type: "gsc",
        source_id: business.id,
        payload: { "business_id" => business.id, "rows" => rows }
      )
    end

    def with_singleton_stub(klass, method_name, replacement)
      original = klass.method(method_name)
      klass.define_singleton_method(method_name) { |*args, **kwargs| replacement.call(*args, **kwargs) }
      yield
    ensure
      klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
        original.call(*args, **kwargs, &block)
      end
    end
  end
end
