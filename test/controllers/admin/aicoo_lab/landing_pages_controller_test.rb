require "test_helper"

module Admin
  module AicooLab
    class LandingPagesControllerTest < ActionDispatch::IntegrationTest
      test "should create landing page" do
        experiment = AicooLabExperiment.create!(title: "LP create test", experiment_type: "lp", acquisition_channel: "sns")

        assert_difference("AicooLabLandingPage.count") do
          post admin_aicoo_lab_experiment_landing_page_url(experiment), params: {
            aicoo_lab_landing_page: landing_page_params
          }
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "LP headline", experiment.reload.aicoo_lab_landing_page.headline
      end

      test "experiment detail shows landing page information" do
        experiment = AicooLabExperiment.create!(title: "LP detail test", experiment_type: "lp", acquisition_channel: "sns")
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params)
        landing_page.aicoo_lab_landing_page_events.create!(event_type: "view")
        landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")
        landing_page.aicoo_lab_signups.create!(email: "detail@example.com")

        get admin_aicoo_lab_experiment_url(experiment)

        assert_response :success
        assert_includes response.body, "LP headline"
        assert_includes response.body, "LP作成済みにする"
        assert_includes response.body, "CTAクリック数"
        assert_includes response.body, "Signup数"
        assert_includes response.body, "1000PV到達状況"
      end

      test "should mark landing page preview ready" do
        experiment = AicooLabExperiment.create!(title: "LP ready test", experiment_type: "lp", acquisition_channel: "sns")
        experiment.create_aicoo_lab_landing_page!(landing_page_params)

        patch preview_ready_admin_aicoo_lab_experiment_landing_page_url(experiment)

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "preview_ready", experiment.reload.status
        assert_equal "preview_ready", experiment.aicoo_lab_landing_page.status
      end

      test "should publish approved preview ready landing page" do
        experiment = AicooLabExperiment.create!(
          title: "LP publish test",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params.merge(status: "preview_ready"))

        assert_difference("AicooAnalyticsSite.count", 1) do
          patch publish_admin_aicoo_lab_experiment_landing_page_url(experiment)
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        landing_page.reload
        assert_equal "published", landing_page.status
        assert landing_page.published_slug.present?
        assert landing_page.published_at.present?
        assert_equal "running", experiment.reload.status
        assert AicooAnalyticsSite.find_by(autolink_source_type: "AicooLabLandingPage", autolink_source_id: landing_page.id)
      end

      test "admin experiment page links to public landing page list and detail" do
        experiment = AicooLabExperiment.create!(
          title: "LP public links test",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params.merge(status: "preview_ready"))
        landing_page.publish!

        get admin_aicoo_lab_experiment_url(experiment)

        assert_response :success
        assert_select "a[href='#{public_landing_pages_path}']"
        assert_select "a[href$='#{public_lp_path(landing_page.published_slug)}']"
      end

      test "published landing page is public and records view event" do
        experiment = AicooLabExperiment.create!(
          title: "LP public view test",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params.merge(status: "preview_ready"))
        landing_page.publish!

        assert_difference("AicooLabLandingPageEvent.where(event_type: 'view').count", 1) do
          get aicoo_lab_published_lp_url(landing_page.published_slug)
        end

        assert_response :success
        assert_includes response.body, "LP headline"
        assert_includes response.body, "公開中"
        assert_equal 1, experiment.reload.current_pv
      end

      test "should unpublish landing page and hide public url" do
        experiment = AicooLabExperiment.create!(
          title: "LP unpublish test",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params.merge(status: "preview_ready"))
        landing_page.publish!

        patch unpublish_admin_aicoo_lab_experiment_landing_page_url(experiment)

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal "unpublished", landing_page.reload.status

        get aicoo_lab_published_lp_url(landing_page.published_slug)
        assert_response :not_found
      end

      test "should pause and resume published landing page" do
        experiment = AicooLabExperiment.create!(
          title: "LP pause test",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params.merge(status: "preview_ready"))
        landing_page.publish!

        assert_difference("AicooLabLandingPagePublicationEvent.where(event_type: 'pause').count", 1) do
          patch pause_admin_aicoo_lab_experiment_landing_page_url(experiment),
                params: { pause_reason: "policy", pause_comment: "表現確認" }
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        landing_page.reload
        assert_equal "paused", landing_page.public_status
        assert_equal "policy", landing_page.pause_reason
        assert_equal "表現確認", landing_page.pause_comment
        assert_equal "admin", landing_page.paused_by

        get public_lp_url(landing_page.published_slug)
        assert_response :success
        assert_includes response.body, "現在公開停止中です"

        assert_difference("AicooLabLandingPagePublicationEvent.where(event_type: 'resume').count", 1) do
          patch resume_admin_aicoo_lab_experiment_landing_page_url(experiment)
        end

        landing_page.reload
        assert_equal "published", landing_page.public_status
        assert_nil landing_page.pause_reason
        assert_nil landing_page.paused_at
        assert_equal "admin", landing_page.resumed_by
      end

      test "admin public landing page list shows pause details and filters" do
        published_experiment = AicooLabExperiment.create!(
          title: "LP list published",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        published = published_experiment.create_aicoo_lab_landing_page!(
          landing_page_params.merge(status: "published", public_status: "published", published_slug: "published-admin-list", published_at: Time.current)
        )
        paused_experiment = AicooLabExperiment.create!(
          title: "LP list paused",
          experiment_type: "lp",
          acquisition_channel: "sns",
          status: "preview_ready",
          approval_status: "approved"
        )
        paused = paused_experiment.create_aicoo_lab_landing_page!(
          landing_page_params.merge(headline: "Paused headline", status: "published", public_status: "published", published_slug: "paused-admin-list", published_at: Time.current)
        )
        paused.pause!(reason: "low_quality", operator: "admin", comment: "品質確認")

        get admin_aicoo_lab_public_landing_pages_url

        assert_response :success
        assert_includes response.body, published.headline
        assert_includes response.body, paused.headline
        assert_includes response.body, "low_quality"
        assert_includes response.body, "admin"

        get admin_aicoo_lab_public_landing_pages_url(public_status: "paused")

        assert_response :success
        assert_includes response.body, paused.headline
        assert_not_includes response.body, published.headline
      end

      test "existing preview url still works" do
        experiment = AicooLabExperiment.create!(title: "LP preview intact test", experiment_type: "lp", acquisition_channel: "sns")
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params)

        get aicoo_lab_preview_url(landing_page.preview_slug)

        assert_response :success
        assert_includes response.body, "LP headline"
        assert_includes response.body, "確認用"
      end

      test "should create metric results from landing page metrics" do
        experiment = AicooLabExperiment.create!(title: "Metric result test", experiment_type: "lp", acquisition_channel: "sns")
        landing_page = experiment.create_aicoo_lab_landing_page!(landing_page_params)
        landing_page.aicoo_lab_landing_page_events.create!(event_type: "view")
        landing_page.aicoo_lab_landing_page_events.create!(event_type: "cta_click")
        landing_page.aicoo_lab_signups.create!(email: "metric@example.com")

        assert_difference("AicooLabResult.count", 3) do
          post create_30d_results_from_metrics_admin_aicoo_lab_experiment_url(experiment)
        end

        assert_redirected_to admin_aicoo_lab_experiment_url(experiment)
        assert_equal %w[conversion_rate ctr pv], experiment.aicoo_lab_results.pluck(:result_type).sort
      end

      private

      def landing_page_params
        {
          headline: "LP headline",
          subheadline: "LP subheadline",
          body: "LP body",
          cta_text: "事前登録する",
          assumed_price_yen: 9_800
        }
      end
    end
  end
end
