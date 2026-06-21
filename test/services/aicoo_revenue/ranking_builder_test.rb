require "test_helper"

module AicooRevenue
  class RankingBuilderTest < ActiveSupport::TestCase
    setup do
      AicooLabSetting.current.update!(hourly_cost_yen: 1_200)
    end

    test "includes candidates and experiments in revenue rankings" do
      candidate = create_candidate(title: "Revenue candidate", expected_90d_profit_yen: 90_000, success_probability: 0.3)
      experiment = create_experiment(title: "Revenue experiment", expected_90d_profit_yen: 80_000, success_probability: 0.4)
      action_candidate = create_action_candidate(title: "Revenue action candidate", immediate_value_yen: 100_000, success_probability: 0.5)

      result = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call

      assert_includes result.revenue_rankings.map(&:title), candidate.title
      assert_includes result.revenue_rankings.map(&:title), experiment.title
      assert_includes result.revenue_rankings.map(&:title), action_candidate.title
      assert_includes result.revenue_rankings.map(&:source), "candidate"
      assert_includes result.revenue_rankings.map(&:source), "experiment"
      assert_includes result.revenue_rankings.map(&:source), "action_candidate"
    end

    test "filters by available minutes and budget" do
      create_candidate(title: "Inside constraints", estimated_work_minutes: 60, budget_yen: 0)
      create_candidate(title: "Too slow", estimated_work_minutes: 240, budget_yen: 0)
      create_candidate(title: "Too expensive", estimated_work_minutes: 60, budget_yen: 1_000)
      create_action_candidate(title: "Action too slow", expected_hours: 3, cost_yen: 0)

      result = RankingBuilder.new(available_minutes: 120, available_budget_yen: 500).call
      titles = result.revenue_rankings.map(&:title)

      assert_includes titles, "Inside constraints"
      assert_not_includes titles, "Too slow"
      assert_not_includes titles, "Too expensive"
      assert_not_includes titles, "Action too slow"
    end

    test "sorts by revenue score descending" do
      low = create_candidate(title: "Low revenue score", expected_90d_profit_yen: 10_000, success_probability: 0.1)
      high = create_candidate(title: "High revenue score", expected_90d_profit_yen: 100_000, success_probability: 0.5)
      action = create_action_candidate(title: "Middle action score", immediate_value_yen: 80_000, success_probability: 0.5)

      titles = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.revenue_rankings.map(&:title)

      assert_operator titles.index(high.title), :<, titles.index(low.title)
      assert_operator titles.index(high.title), :<, titles.index(action.title)
    end

    test "does not change lab priority score" do
      candidate = create_candidate(title: "Lab score unchanged", expected_90d_profit_yen: 50_000, success_probability: 0.3)
      lab_priority_score = candidate.lab_priority_score
      scoring_speed_score = candidate.scoring_speed_score

      RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call

      assert_equal lab_priority_score, candidate.reload.lab_priority_score
      assert_equal scoring_speed_score, candidate.reload.scoring_speed_score
    end

    test "handles zero budget roi without division error" do
      candidate = create_candidate(title: "Free ROI", budget_yen: 0)

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.roi_rankings.find { |ranking| ranking.title == candidate.title }

      assert_equal Float::INFINITY, row.roi_score
    end

    test "adds neglect loss to revenue score" do
      candidate = create_candidate(
        title: "Neglect loss candidate",
        expected_90d_profit_yen: 100_000,
        success_probability: 0.2,
        estimated_work_minutes: 60,
        budget_yen: 0,
        neglect_loss_90d_yen: 30_000
      )

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.revenue_rankings.find { |ranking| ranking.title == candidate.title }

      assert_equal 50_000.to_d, row.revenue_total_value_yen
      assert_equal 50_000.to_d / 1_200, row.revenue_score
      assert_equal 50_000.to_d, row.expected_hourly_profit
      assert_equal Float::INFINITY, row.roi_score
    end

    test "zero neglect loss keeps previous revenue formula" do
      candidate = create_candidate(
        title: "Zero neglect candidate",
        expected_90d_profit_yen: 100_000,
        success_probability: 0.2,
        estimated_work_minutes: 60,
        budget_yen: 0,
        neglect_loss_90d_yen: 0
      )

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.revenue_rankings.find { |ranking| ranking.title == candidate.title }

      assert_equal 20_000.to_d, row.revenue_total_value_yen
      assert_equal 20_000.to_d / 1_200, row.revenue_score
    end

    test "neglect loss works for all sources" do
      candidate = create_candidate(title: "Candidate neglect", neglect_loss_90d_yen: 10_000)
      experiment = create_experiment(title: "Experiment neglect", neglect_loss_90d_yen: 20_000)
      action = create_action_candidate(title: "Action neglect", neglect_loss_90d_yen: 30_000)

      result = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call
      rows = result.revenue_rankings.index_by(&:title)

      assert_equal 10_000, rows.fetch(candidate.title).neglect_loss_90d_yen
      assert_equal 20_000, rows.fetch(experiment.title).neglect_loss_90d_yen
      assert_equal 30_000, rows.fetch(action.title).neglect_loss_90d_yen
    end

    test "estimates and stores neglect loss from DataHub snapshots" do
      action = create_action_candidate(title: "Estimated neglect action", immediate_value_yen: 100_000, success_probability: 0.5)
      create_gsc_snapshot(action.business, clicks: 100, impressions: 1_000, position: 2, captured_at: 2.days.ago)
      create_gsc_snapshot(action.business, clicks: 40, impressions: 800, position: 7, captured_at: 1.day.ago)

      result = NeglectLossEstimator.new(action).estimate_and_store!

      assert_operator result.estimated_neglect_loss_90d_yen, :>, 0
      assert result.auto_generated
      assert_equal result.estimated_neglect_loss_90d_yen, action.reload.estimated_neglect_loss_90d_yen
      assert action.neglect_loss_auto_generated
    end

    test "estimates neglect loss for lab experiment from landing page snapshots" do
      experiment = create_experiment(title: "Estimated LP experiment", expected_90d_profit_yen: 100_000, success_probability: 0.5)
      landing_page = AicooLabLandingPage.create!(
        aicoo_lab_experiment: experiment,
        headline: "LP",
        subheadline: "Sub",
        body: "Body",
        cta_text: "CTA"
      )
      create_landing_page_snapshot(landing_page, pv: 1_000, signup_rate: 0.05, captured_at: 2.days.ago)
      create_landing_page_snapshot(landing_page, pv: 500, signup_rate: 0.01, captured_at: 1.day.ago)

      result = NeglectLossEstimator.new(experiment).estimate_and_store!

      assert_operator result.estimated_neglect_loss_90d_yen, :>, 0
      assert experiment.reload.neglect_loss_auto_generated
    end

    test "ranking uses estimated neglect loss when manual value is zero" do
      action = create_action_candidate(title: "Auto neglect ranking", immediate_value_yen: 100_000, success_probability: 0.5)
      create_gsc_snapshot(action.business, clicks: 100, impressions: 1_000, position: 2, captured_at: 2.days.ago)
      create_gsc_snapshot(action.business, clicks: 40, impressions: 800, position: 7, captured_at: 1.day.ago)

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.revenue_rankings.find { |ranking| ranking.title == action.title }

      assert_equal 0, row.manual_neglect_loss_90d_yen
      assert_operator row.estimated_neglect_loss_90d_yen, :>, 0
      assert_equal row.estimated_neglect_loss_90d_yen, row.neglect_loss_90d_yen
      assert_equal (row.expected_90d_profit_yen.to_d * row.success_probability.to_d) + row.estimated_neglect_loss_90d_yen,
                   row.revenue_total_value_yen
    end

    test "old unfinished row with neglect loss becomes neglect alert" do
      candidate = create_candidate(
        title: "Old neglect alert",
        neglect_loss_90d_yen: 10_000,
        neglect_loss_reason: "SEO放置による順位低下リスク"
      )
      candidate.update_columns(updated_at: 15.days.ago)

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.neglect_alerts.find { |ranking| ranking.title == candidate.title }

      assert row.neglect_alert
      assert_operator row.neglected_days, :>=, 14
      assert_equal "SEO放置による順位低下リスク", row.neglect_loss_reason
      assert_includes row.neglect_alert_reason, "SEO放置"
    end

    test "fresh row with zero neglect loss does not become neglect alert" do
      candidate = create_candidate(title: "Fresh no neglect alert", neglect_loss_90d_yen: 0)

      titles = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.neglect_alerts.map(&:title)

      assert_not_includes titles, candidate.title
    end

    test "finished statuses do not become neglect alert" do
      action = create_action_candidate(title: "Done action neglect", status: "done", neglect_loss_90d_yen: 20_000)
      candidate = create_candidate(title: "Rejected candidate neglect", neglect_loss_90d_yen: 20_000)
      experiment = create_experiment(title: "Success experiment neglect", neglect_loss_90d_yen: 20_000)
      candidate.update_columns(status: "rejected", updated_at: 30.days.ago)
      experiment.update_columns(status: "success", updated_at: 30.days.ago)
      action.update_columns(updated_at: 30.days.ago)

      titles = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.neglect_alerts.map(&:title)

      assert_not_includes titles, action.title
      assert_not_includes titles, candidate.title
      assert_not_includes titles, experiment.title
    end

    test "normalizes action candidate values" do
      action_candidate = create_action_candidate(
        title: "Normalized action candidate",
        immediate_value_yen: 120_000,
        success_probability: 0.5,
        expected_hours: 1.5,
        cost_yen: 300
      )

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 500).call.revenue_rankings.find { |ranking| ranking.title == action_candidate.title }

      assert_equal "action_candidate", row.source
      assert_equal "seo_article", row.experiment_type
      assert_equal action_candidate.business.name, row.market_category
      assert_equal 60_000, row.expected_90d_profit_yen
      assert_equal 0.5.to_d, row.success_probability
      assert_equal 0, row.neglect_loss_90d_yen
      assert_equal 30_000.to_d, row.revenue_total_value_yen
      assert_equal 90, row.estimated_work_minutes
      assert_equal 300, row.budget_yen
      assert_equal 1_800.to_d, row.time_cost_yen
      assert_equal 60_000.to_d * 0.5 / 2_100, row.revenue_score
    end

    test "normalizes action candidate percent probability" do
      action_candidate = create_action_candidate(title: "Percent probability action", immediate_value_yen: 100_000, success_probability: 0.5)
      action_candidate.update_column(:success_probability, 50)

      row = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0).call.revenue_rankings.find { |ranking| ranking.title == action_candidate.title }

      assert_equal 0.5.to_d, row.success_probability
    end

    test "source filter returns only action candidates" do
      create_candidate(title: "Filtered lab candidate")
      action_candidate = create_action_candidate(title: "Filtered action candidate")

      result = RankingBuilder.new(available_minutes: 180, available_budget_yen: 0, source: "action_candidate").call
      titles = result.revenue_rankings.map(&:title)

      assert_includes titles, action_candidate.title
      assert_not_includes titles, "Filtered lab candidate"
      assert result.revenue_rankings.all? { |row| row.source == "action_candidate" }
    end

    private

    def create_candidate(attributes = {})
      AicooLabExperimentCandidate.create!(
        {
          title: "Revenue candidate",
          description: "Revenue candidate description",
          experiment_type: "lp",
          market_category: "revenue market",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60,
          rationale: "Revenue rationale"
        }.merge(attributes)
      )
    end

    def create_experiment(attributes = {})
      AicooLabExperiment.create!(
        {
          title: "Revenue experiment",
          description: "Revenue experiment description",
          experiment_type: "lp",
          market_category: "revenue market",
          acquisition_channel: "seo",
          expected_90d_profit_yen: 50_000,
          success_probability: 0.25,
          budget_yen: 0,
          estimated_work_minutes: 60
        }.merge(attributes)
      )
    end

    def create_action_candidate(attributes = {})
      business = Business.create!(name: "Revenue business")
      ActionCandidate.create!(
        {
          business:,
          title: "Revenue action candidate",
          action_type: "seo_article",
          status: "idea",
          immediate_value_yen: 80_000,
          success_probability: 0.25,
          expected_hours: 1,
          cost_yen: 0
        }.merge(attributes)
      )
    end

    def create_gsc_snapshot(business, clicks:, impressions:, position:, captured_at:)
      AicooDataSnapshot.create!(
        source_type: "gsc",
        source_id: AicooDataSnapshot.maximum(:source_id).to_i + 1,
        captured_at:,
        payload: {
          business_id: business.id,
          metrics: {
            clicks:,
            impressions:,
            ctr: clicks.to_d / impressions.to_d,
            position:
          }
        }
      )
    end

    def create_landing_page_snapshot(landing_page, pv:, signup_rate:, captured_at:)
      AicooDataSnapshot.create!(
        source_type: "landing_page",
        source_id: landing_page.id,
        captured_at:,
        payload: {
          landing_page_id: landing_page.id,
          experiment_id: landing_page.aicoo_lab_experiment_id,
          pv:,
          signup_rate:
        }
      )
    end
  end
end
