require "test_helper"

module Aicoo
  class ActionExpectedValueRankingTest < ActiveSupport::TestCase
    Item = Data.define(
      :stable_id,
      :rank,
      :priority,
      :business_name,
      :expected_value_yen,
      :score,
      :record,
      :action_expected_value_delta_yen,
      :confidence,
      :valuation_status
    )

    test "paginates twenty items and keeps global rank" do
      items = 45.times.map do |index|
        Item.new(
          stable_id: "action_candidate:#{index + 1}",
          rank: nil,
          priority: "improvement",
          business_name: "Business",
          expected_value_yen: 100_000 - index,
          score: 100_000 - index,
          record: nil,
          action_expected_value_delta_yen: 100_000 - index,
          confidence: 0.8,
          valuation_status: "positive"
        )
      end

      first_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 1).call
      second_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 2).call
      third_page = ActionExpectedValueRanking.new(items:, mode: "revenue", page: 3).call

      assert_equal 45, first_page.total_count
      assert_equal 20, first_page.items.size
      assert_equal 3, first_page.total_pages
      assert_equal 1, first_page.items.first.rank
      assert_equal "action_candidate:1", first_page.items.first.stable_id
      assert_equal 20, second_page.items.size
      assert_equal 21, second_page.items.first.rank
      assert_equal "action_candidate:21", second_page.items.first.stable_id
      assert_equal 5, third_page.items.size
      assert_equal 41, third_page.items.first.rank
      assert_equal "action_candidate:41", third_page.items.first.stable_id
    end

    test "ranks avoided loss by positive action delta instead of raw negative loss" do
      recovery = item(
        stable_id: "daily_run_issue:stuck",
        delta: 700_000,
        no_action: -1_000_000,
        action: -200_000,
        cost: 100_000,
        confidence: 0.8
      )
      neutral = item(stable_id: "action_candidate:neutral", delta: 0, confidence: 1)
      negative = item(stable_id: "new_business:negative", delta: -500, confidence: 0.9)

      result = ActionExpectedValueRanking.new(items: [ negative, neutral, recovery ], mode: "revenue").call

      assert_equal [ "daily_run_issue:stuck", "action_candidate:neutral", "new_business:negative" ], result.items.map(&:stable_id)
      assert_equal 700_000, result.items.first.action_expected_value_delta_yen
    end

    test "excludes unvalued items from ranking instead of treating them as zero" do
      unvalued = item(stable_id: "action_candidate:unvalued", delta: 0, confidence: 1, valuation_status: "unvalued")
      valued = item(stable_id: "action_candidate:valued", delta: 1, confidence: 0.5)

      result = ActionExpectedValueRanking.new(items: [ unvalued, valued ], mode: "revenue").call

      assert_equal [ "action_candidate:valued" ], result.items.map(&:stable_id)
    end

    test "excludes action candidate records with external or invalid target urls" do
      external = action_candidate(
        title: "外部URL改善",
        metadata: { "target_url_type" => "external_reference", "target_url" => nil }
      )
      invalid = action_candidate(
        title: "不正URL改善",
        metadata: { "target_url_type" => "invalid", "target_url" => nil }
      )
      valid = action_candidate(
        title: "自社URL改善",
        metadata: { "target_url_type" => "own_existing", "target_url" => "/" }
      )

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:external", delta: 10_000, confidence: 1, record: external),
          item(stable_id: "action_candidate:invalid", delta: 9_000, confidence: 1, record: invalid),
          item(stable_id: "action_candidate:valid", delta: 1_000, confidence: 1, record: valid)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:valid" ], result.items.map(&:stable_id)
    end

    test "excludes rejected and repair cleaned action candidates from ranking" do
      rejected = action_candidate(
        title: "却下済み候補",
        metadata: { "target_url_type" => "own_existing", "target_url" => "/" }
      )
      rejected.update!(status: "rejected")
      repaired = action_candidate(
        title: "修復済み外部候補",
        metadata: {
          "target_url_type" => "own_existing",
          "target_url" => nil,
          "repair_reason" => "external_reference",
          "rejection_reason" => "external_reference_target"
        }
      )
      valid = action_candidate(
        title: "表示する候補",
        metadata: { "target_url_type" => "own_existing", "target_url" => "/" }
      )

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:rejected", delta: 30_000, confidence: 1, record: rejected),
          item(stable_id: "action_candidate:repaired", delta: 20_000, confidence: 1, record: repaired),
          item(stable_id: "action_candidate:valid", delta: 10_000, confidence: 1, record: valid)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:valid" ], result.items.map(&:stable_id)
    end

    test "excludes missing target candidate from normal ranking" do
      missing_target = action_candidate(
        title: "対象未特定だが未実行の施策",
        metadata: { "target_url" => nil }
      )

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:missing_target", delta: 10_000, confidence: 1, record: missing_target)
        ],
        mode: "revenue"
      ).call

      assert_empty result.items
    end

    test "ranks executable article opportunity above preparation candidate by normalized score" do
      executable = action_candidate(
        title: "記事のCTR改善",
        metadata: {
          "value_model_name" => ActionExpectedValueRanking::ARTICLE_OPPORTUNITY_MODEL_NAME,
          "analysis_source" => "article_analytics_snapshot",
          "snapshot_id" => 123,
          "expected_improvement_score" => 8.5,
          "improvement_potential_score" => 6.0,
          "article_path" => "/articles/umeda-smoking-cafe",
          "action_plan" => { "target" => "/articles/umeda-smoking-cafe" },
          "ranking_reason" => "表示上位でCTR改善余地があります。"
        }
      )
      executable.update!(action_type: "article_update")
      preparation = action_candidate(
        title: "対象ページを特定する",
        metadata: { "execution_readiness" => "needs_target", "target_url" => nil }
      )
      preparation.update!(action_type: "data_preparation")

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:preparation", delta: 900_000, confidence: 1, record: preparation),
          item(stable_id: "action_candidate:executable", delta: 0, confidence: 0.6, record: executable)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:executable" ], result.items.map(&:stable_id)
    end

    test "uses one fallback only when normal candidate does not exist" do
      fallback = action_candidate(
        title: "分析データからTODOを1件具体化",
        metadata: { "today_fallback" => true, "target_url" => "/" }
      )
      second_fallback = action_candidate(
        title: "fallback action",
        metadata: { "today_fallback" => true, "target_url" => "/" }
      )

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:fallback", delta: 10_000, confidence: 1, record: fallback),
          item(stable_id: "action_candidate:second_fallback", delta: 20_000, confidence: 1, record: second_fallback)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:second_fallback" ], result.items.map(&:stable_id)
    end

    test "deduplicates same article action by query and planned url" do
      first = action_candidate(
        title: "「吸えログ 比較」向けの記事を1本作成する",
        metadata: {
          "query" => "吸えログ 比較",
          "planned_url" => "/articles/suelog-vs-tabelog",
          "work_type" => "new_article",
          "url_classification" => "proposed_new"
        }
      )
      first.update!(action_type: "new_article_candidate")
      second = action_candidate(
        title: "吸えログ 比較の記事を作成する",
        metadata: {
          "target_query" => "吸えログ 比較",
          "proposed_url" => "/articles/suelog-vs-tabelog",
          "work_type" => "new_article",
          "url_classification" => "proposed_new"
        }
      )
      second.update!(action_type: "article_create")
      different = action_candidate(
        title: "「吸えログ 比較」の内部リンクを追加する",
        metadata: {
          "query" => "吸えログ 比較",
          "planned_url" => "/articles/suelog-vs-tabelog",
          "work_type" => "internal_link",
          "url_classification" => "proposed_new"
        }
      )
      different.update!(action_type: "seo_improvement")

      result = ActionExpectedValueRanking.new(
        items: [
          item(stable_id: "action_candidate:first", delta: 10_000, confidence: 0.8, record: first),
          item(stable_id: "action_candidate:second", delta: 20_000, confidence: 0.7, record: second),
          item(stable_id: "action_candidate:different", delta: 5_000, confidence: 0.9, record: different)
        ],
        mode: "revenue"
      ).call

      assert_equal [ "action_candidate:second", "action_candidate:different" ], result.items.map(&:stable_id)
    end

    private

    def item(stable_id:, delta:, confidence:, valuation_status: nil, no_action: 0, action: nil, cost: 0, record: nil)
      Item.new(
        stable_id:,
        rank: nil,
        priority: "improvement",
        business_name: "Business",
        expected_value_yen: delta,
        score: delta,
        record:,
        action_expected_value_delta_yen: delta,
        confidence:,
        valuation_status: valuation_status || (delta.positive? ? "positive" : (delta.negative? ? "negative" : "neutral"))
      )
    end

    def action_candidate(title:, metadata:)
      ActionCandidate.create!(
        business: businesses(:suelog),
        title:,
        action_type: "seo_improvement",
        generation_source: "business_analyzer",
        immediate_value_yen: 1_000,
        success_probability: 0.5,
        expected_hours: 1,
        metadata:
      )
    end
  end
end
