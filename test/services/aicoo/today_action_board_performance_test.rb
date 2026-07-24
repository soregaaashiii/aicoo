require "test_helper"

module Aicoo
  class TodayActionBoardPerformanceTest < ActiveSupport::TestCase
    setup do
      @business = businesses(:suelog)
      ActionCandidate.update_all(status: "archived")
      AicooDailyRun.update_all(status: "success")
      insert_article_candidates(100)
    end

    test "query count does not grow with the number of article candidates" do
      counts = [ 10, 50, 100 ].index_with do |candidate_count|
        activate_candidates(candidate_count)
        run_board
        query_count, write_count, board = count_queries { run_board }

        assert_equal candidate_count, board.items.count { |item| item.record.is_a?(ActionCandidate) }
        assert_equal 0, write_count
        query_count
      end
      assert_operator counts.fetch(100), :<=, counts.fetch(10) + 10
      assert_operator counts.fetch(100), :<=, 100
    end

    private

    def insert_article_candidates(count)
      now = Time.current
      rows = count.times.map do |index|
        article_id = 10_000 + index
        {
          business_id: @business.id,
          title: "記事#{article_id}のタイトルを改善する",
          status: "archived",
          action_type: "article_update",
          generation_source: "business_analyzer",
          department: "revenue",
          expected_hours: 0.3,
          success_probability: 0.55,
          metadata: {
            "value_model_name" => TodayActionBoard::ARTICLE_OPPORTUNITY_MODEL_NAME,
            "analysis_source" => "article_analytics_snapshot",
            "snapshot_id" => article_id,
            "article_id" => article_id,
            "article_path" => "/",
            "opportunity_type" => "ctr_improvement",
            "opportunity_label" => "CTR改善",
            "expected_improvement_score" => 5.0,
            "search_demand_score" => 1.0,
            "improvement_potential_score" => 5.0,
            "success_probability" => 0.55,
            "estimated_work_hours" => 0.3,
            "business_value" => 1.3,
            "ranking_reason" => "記事タイトルの改善余地があります。",
            "action_plan" => {
              "summary" => "記事#{article_id}のタイトルを改善する",
              "target" => "/",
              "owner_next_step" => "タイトル案を確認する",
              "execution_steps" => [ "タイトル案を確認する" ]
            }
          },
          created_at: now,
          updated_at: now
        }
      end
      ActionCandidate.insert_all!(rows)
      @candidate_ids = ActionCandidate.where(title: rows.map { |row| row.fetch(:title) }).order(:id).ids
    end

    def activate_candidates(count)
      ActionCandidate.where(id: @candidate_ids).update_all(status: "archived")
      ActionCandidate.where(id: @candidate_ids.first(count)).update_all(status: "proposal")
    end

    def run_board
      ActiveRecord::Base.connection.uncached do
        TodayActionBoard.new(mode: "revenue", per_page: 200).call
      end
    end

    def count_queries
      count = 0
      write_count = 0
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]

        count += 1
        write_count += 1 if payload[:sql].match?(/\A(?:INSERT|UPDATE|DELETE)/)
      end

      result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      [ count, write_count, result ]
    end
  end
end
