require "test_helper"

module Aicoo
  class IndependentActivityCandidateGeneratorTest < ActiveSupport::TestCase
    test "generates a normal candidate from repeated positive independent learning" do
      business = businesses(:suelog)
      rows = positive_learning_rows(business)

      assert_difference("ActionCandidate.count", 1) do
        result = run_generator(rows:, apply: true)
        generated = result.rows.first

        assert generated.eligible
        assert generated.candidate_generated
        assert_not generated.duplicate
        assert_equal 3, generated.sample_count
        assert_equal 8.0, generated.roi
        assert_equal 0.8, generated.confidence
      end

      candidate = ActionCandidate.order(:id).last
      learning = candidate.metadata.fetch("independent_learning")
      assert_equal "independent_learning", candidate.generation_source
      assert_equal "proposal", candidate.status
      assert_equal "other", candidate.action_type
      assert_equal 12_000, candidate.immediate_value_yen
      assert_operator candidate.expected_profit_yen, :>, 0
      assert_equal 3, learning["sample_count"]
      assert_equal 8.0, learning["roi"]
      assert_equal 0.8, learning["confidence"]
      assert_equal false, candidate.metadata["codex_eligible"]
      assert_equal "manual_operation", candidate.metadata["execution_mode"]
    end

    test "does not create a duplicate active strategy candidate" do
      business = businesses(:suelog)
      rows = positive_learning_rows(business)

      run_generator(rows:, apply: true)

      assert_no_difference("ActionCandidate.count") do
        result = run_generator(rows:, apply: true)
        duplicate = result.rows.first

        assert duplicate.candidate_generated
        assert duplicate.duplicate
        assert_equal "duplicate_active_candidate", duplicate.skip_reason
        assert_equal 1, result.summary.duplicate_count
      end
    end

    test "rejects learning before minimum sample count" do
      business = businesses(:suelog)
      rows = positive_learning_rows(business).first(2)

      assert_no_difference("ActionCandidate.count") do
        result = run_generator(rows:, apply: true)
        rejected = result.rows.first

        assert_not rejected.eligible
        assert_equal "sample_count_below_minimum", rejected.skip_reason
        assert_equal 1, result.summary.rejected_count
      end
    end

    test "maps learned user activities to supported action types" do
      business = businesses(:suelog)
      mappings = {
        "shop_created" => [ "Shop", "other" ],
        "shop_profile_updated" => [ "Shop", "shop_data_cleanup" ],
        "article_created" => [ "Article", "article_create" ],
        "article_updated" => [ "Article", "article_update" ],
        "title_changed" => [ "Article", "seo_improvement" ],
        "seo_improvement" => [ "Article", "seo_improvement" ],
        "internal_link_added" => [ "Article", "article_update" ]
      }

      mappings.each do |activity_type, (source_model, expected_action_type)|
        rows = 3.times.map do |index|
          learning_row(
            business:,
            key: "#{activity_type}-#{index}",
            roi: 5 + index,
            confidence: 0.8,
            revenue_delta: 10_000 + index,
            activity_type:,
            source_model:
          )
        end

        result = run_generator(rows:, apply: false)
        assert_equal expected_action_type, result.rows.first.action_type
      end
    end

    private

    def run_generator(rows:, apply:)
      diagnostic = Object.new
      diagnostic.define_singleton_method(:call) do
        Struct.new(:rows).new(rows)
      end

      IndependentActivityLearningDiagnostic.stub(:new, ->(**) { diagnostic }) do
        IndependentActivityCandidateGenerator.call(apply:)
      end
    end

    def positive_learning_rows(business)
      [
        learning_row(business:, key: "learning-a", roi: 7.0, confidence: 0.6, revenue_delta: 10_000),
        learning_row(business:, key: "learning-b", roi: 8.0, confidence: 0.7, revenue_delta: 12_000),
        learning_row(business:, key: "learning-c", roi: 9.0, confidence: 0.8, revenue_delta: 14_000)
      ]
    end

    def learning_row(business:, key:, roi:, confidence:, revenue_delta:, activity_type: "shop_created", source_model: "Shop")
      IndependentActivityLearningDiagnostic::Row.new(
        group_key: key,
        business_id: business.id,
        area: "学習テスト梅田",
        station: "梅田",
        genre: "独立学習居酒屋",
        smoking_type: "紙タバコ可",
        activity_type:,
        source_app: "suelog",
        source_model:,
        excluded_reason: nil,
        included_reason: "suelog_user_activity",
        is_internal_event: false,
        is_suelog_activity: true,
        shop_count: 1,
        article_count: 0,
        created_count: 1,
        updated_count: 0,
        deleted_count: 0,
        learning_status: "evaluated",
        confidence:,
        roi:,
        outcome: {},
        evaluations: {
          7 => {
            "status" => "evaluated",
            "evaluated_at" => Time.current.iso8601,
            "metrics" => { "revenue_yen" => { "delta" => revenue_delta } },
            "confidence" => confidence,
            "roi" => roi,
            "estimated_work_seconds" => 1_800,
            "work_cost_yen" => 1_500
          }
        }
      )
    end
  end
end
