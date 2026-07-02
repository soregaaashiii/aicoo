require "test_helper"

module Aicoo
  class IntegratedDecisionEngineTest < ActiveSupport::TestCase
    test "generates new business candidate from new business serp query" do
      business = businesses(:suelog)
      serp_query = business.serp_queries.create!(
        query: "警備 AI SaaS #{SecureRandom.hex(4)}",
        category: "new_business",
        priority: 1,
        daily_limit: 5
      )
      serp_run = SerpRun.create!(
        status: "success",
        executed_by: "manual",
        started_at: 10.minutes.ago,
        finished_at: Time.current,
        query_count: 1,
        success_count: 1,
        failure_count: 0
      )
      analysis = business.serp_analyses.create!(
        serp_run:,
        keyword: serp_query.query,
        search_engine: "google",
        device: "desktop",
        provider: "serper",
        status: "success",
        result_count: 3,
        analyzed_at: Time.current,
        raw_summary: { "serp_query_id" => serp_query.id }
      )
      analysis.serp_results.create!(position: 1, title: "警備AIツール", url: "https://example.com", snippet: "警備のAI化")

      candidates = Aicoo::IntegratedDecisionEngine.new(serp_run:, daily_run: nil).generate_unified_candidates!

      new_business = candidates.find { |candidate| candidate.metadata["candidate_kind"] == "new_business" }
      assert new_business
      assert_equal "integrated_decision", new_business.generation_source
      assert_equal "new_business", new_business.department
      assert_equal "build_lp", new_business.action_type
      assert_equal serp_query.query, new_business.metadata["source_query"]
    end
  end
end
