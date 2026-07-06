require "test_helper"

module Aicoo
  class UrlContaminationTracerTest < ActiveSupport::TestCase
    TARGET_URL = "it-trend.jp/log_management/article/84-0008"

    test "traces contaminated action candidate and archives related execution records" do
      business = businesses(:suelog)
      candidate = business.action_candidates.create!(
        title: "吸えログ 比較のSERP差分対応",
        description: "ログ管理システム比較が混入",
        action_type: "seo_article",
        generation_source: "integrated_decision",
        status: "idea",
        metadata: {
          "source_query" => "吸えログ 比較",
          "serp_top_results" => [
            { "title" => "ログ管理システム比較", "url" => "https://#{TARGET_URL}" }
          ]
        }
      )
      task = AutoRevisionTask.create!(
        action_candidate: candidate,
        business:,
        title: candidate.title,
        execution_prompt: "混入URL https://#{TARGET_URL}",
        status: "ready_for_codex",
        risk_level: "low",
        priority_score: 10
      )
      execution = ActionExecution.create!(
        action_candidate: candidate,
        status: "ready",
        execution_prompt: "混入URL https://#{TARGET_URL}"
      )

      result = UrlContaminationTracer.call(url: TARGET_URL, fix: true)

      assert_equal "test", result.environment
      assert result.matches.any? { |match| match[:table] == "action_candidates" && match[:id] == candidate.id }
      assert_match(/IntegratedDecisionEngine/, result.cause)
      assert_equal "archived", candidate.reload.status
      assert_equal "canceled", task.reload.status
      assert_equal "cancelled", execution.reload.status
    end
  end
end
