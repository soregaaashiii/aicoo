require "test_helper"

module Admin
  module AicooLab
    class ExperimentsControllerTest < ActionDispatch::IntegrationTest
      test "should get index" do
        get admin_aicoo_lab_experiments_url
        assert_response :success
        assert_includes response.body, "この画面でやること"
        assert_includes response.body, "アイデアをLP化し、市場の反応を検証してください"
      end

      test "index shows next operation and Japanese statuses" do
        AicooLabExperiment.create!(
          title: "Next operation preview",
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "preview_ready",
          approval_status: "not_required"
        )
        AicooLabExperiment.create!(
          title: "Next operation running",
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "running",
          approval_status: "approved"
        )

        get admin_aicoo_lab_experiments_url

        assert_response :success
        assert_includes response.body, "新規事業"
        assert_includes response.body, "今やること"
        assert_includes response.body, "事業アイデア"
        assert_includes response.body, "次にやる操作"
        assert_includes response.body, "LP作成済み"
        assert_includes response.body, "承認済み"
        assert_includes response.body, "LPを確認してレビューする"
        assert_includes response.body, "LP URLに流入させる / 採点待ちを確認"
      end

      test "should get new" do
        get new_admin_aicoo_lab_experiment_url
        assert_response :success
      end

      test "should create experiment" do
        assert_difference("AicooLabExperiment.count") do
          post admin_aicoo_lab_experiments_url, params: {
            aicoo_lab_experiment: {
              title: "New lab experiment",
              experiment_type: "lp",
              acquisition_channel: "seo",
              expected_90d_profit_yen: 50_000,
              success_probability: 0.4,
              budget_yen: 1_000,
              estimated_work_minutes: 120,
              neglect_loss_90d_yen: 8_000,
              neglect_loss_reason: "承認遅延による機会損失"
            }
          }
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(AicooLabExperiment.last)
        assert_equal 8_000, AicooLabExperiment.last.neglect_loss_90d_yen
        assert_equal "承認遅延による機会損失", AicooLabExperiment.last.neglect_loss_reason
      end

      test "should move experiment to approval pending" do
        experiment = AicooLabExperiment.create!(title: "Approval test", experiment_type: "lp", acquisition_channel: "seo")

        patch approval_pending_admin_aicoo_lab_experiment_url(experiment)

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "pending", experiment.reload.approval_status
      end

      test "show displays next action for approved not started experiment" do
        experiment = AicooLabExperiment.create!(
          title: "Show next action",
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "approval_pending",
          approval_status: "approved"
        )

        get admin_aicoo_lab_experiment_url(experiment)

        assert_response :success
        assert_includes response.body, "次に押すべきボタン"
        assert_includes response.body, "検証開始"
        assert_includes response.body, "検証開始待ち"
      end

      test "show displays traffic URL guidance for running experiment" do
        experiment = AicooLabExperiment.create!(
          title: "Running traffic URL",
          experiment_type: "lp",
          acquisition_channel: "seo",
          status: "running",
          approval_status: "approved"
        )
        experiment.create_aicoo_lab_landing_page!(
          headline: "Traffic headline",
          subheadline: "Traffic subheadline",
          body: "Traffic body",
          cta_text: "事前登録する",
          status: "preview_ready"
        )

        get admin_aicoo_lab_experiment_url(experiment)

        assert_response :success
        assert_includes response.body, "このLP URLに流入させてください"
        assert_includes response.body, "外部に自動公開・自動集客されるわけではありません"
        assert_includes response.body, "PV"
        assert_includes response.body, "CTAクリック"
        assert_includes response.body, "Signup"
      end
    end
  end
end
