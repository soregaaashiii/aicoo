require "test_helper"

module Aicoo
  class IntegratedDecisionEngineTest < ActiveSupport::TestCase
    test "does not generate new business candidate because serp discovery owns that flow" do
      business = businesses(:suelog)
      business.update!(business_type: "exploration")
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

      assert_empty candidates.select { |candidate| candidate.metadata["candidate_kind"] == "new_business" }
    end

    test "does not generate suelog candidate from unrelated branded serp results" do
      business = businesses(:suelog)
      serp_query = business.serp_queries.create!(
        query: "吸えログ 比較",
        category: "existing_business",
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
      analysis.serp_results.create!(position: 1, title: "ログ管理システム比較", url: "https://it-trend.jp/log_management/article/84-0008", snippet: "操作ログと監査ログを比較")
      analysis.serp_results.create!(position: 2, title: "勤怠ログ管理ツール比較", url: "https://example.com/time-log", snippet: "業務日報とログ管理")

      candidates = Aicoo::IntegratedDecisionEngine.new(serp_run:, daily_run: nil).generate_unified_candidates!

      assert_empty candidates
    end

    test "ignores serp analysis when raw serp query belongs to another business" do
      suelog = businesses(:suelog)
      other = businesses(:cards)
      serp_query = other.serp_queries.create!(
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
      analysis = suelog.serp_analyses.create!(
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

      assert_empty candidates
    end
  end
end
