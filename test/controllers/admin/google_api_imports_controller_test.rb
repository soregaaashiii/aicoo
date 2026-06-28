require "test_helper"

module Admin
  class GoogleApiImportsControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @previous_queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      clear_enqueued_jobs
      clear_performed_jobs
      @business = businesses(:suelog)
      @business.update!(gsc_site_url: "sc-domain:suelog.test")
      @credential = AicooGoogleCredential.create!(
        name: "AICOO共通Google認証",
        google_cloud_project_id: "aicoo-500805",
        client_id: "338488400527-client.apps.googleusercontent.com",
        client_secret: "secret",
        refresh_token: "refresh-token",
        connected_at: Time.current
      )
      AicooAnalyticsSite.create!(
        business: @business,
        name: "Suelog",
        public_url: "https://suelog.test",
        domain: "suelog.test",
        gsc_site_url: @business.gsc_site_url,
        ga4_property_id: "properties/123",
        authentication_mode: "shared"
      )
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
      ActiveJob::Base.queue_adapter = @previous_queue_adapter
    end

    test "shows google api import screen separated from csv import" do
      GoogleApiImportRun.create!(
        business: @business,
        status: "success",
        source_types: %w[gsc ga4],
        fetched_days: 3,
        started_at: 10.minutes.ago,
        finished_at: 9.minutes.ago,
        updated_metric_count: 2
      )

      get admin_google_api_imports_url

      assert_response :success
      assert_includes response.body, "Google API直取得"
      assert_includes response.body, "CSV貼り付けは使いません"
      assert_includes response.body, @business.name
      assert_includes response.body, "sc-domain:suelog.test"
      assert_includes response.body, "properties/123"
      assert_includes response.body, "Google APIから取得"
      assert_includes response.body, "現在使用中のGoogle OAuth Client"
      assert_includes response.body, @credential.client_id
      assert_includes response.body, @credential.effective_google_cloud_project_id
      assert_includes response.body, "action=\"#{admin_google_api_imports_path}\""
      assert_includes response.body, "data-aicoo-submit-lock=\"true\""
      assert_includes response.body, "data-aicoo-loading-label=\"Google API取得中...\""
      assert_includes response.body, "aicoo-loading-feedback"
      assert_includes response.body, "取得状態"
      assert_includes response.body, "成功"
      assert_includes response.body, "更新 2件"
      refute_includes response.body, "action=\"#{admin_google_api_import_path(@business)}\""
      assert_includes response.body, admin_analytics_imports_path
    end

    test "enqueues google api import for a business" do
      assert_difference("GoogleApiImportRun.count", 1) do
        assert_enqueued_with(job: AicooAnalytics::BusinessGoogleApiImportJob) do
          post admin_google_api_imports_url, params: { business_id: @business.id }
        end
      end

      run = GoogleApiImportRun.last
      assert_equal @business, run.business
      assert_equal "queued", run.status
      assert_equal %w[gsc ga4], run.source_types
      assert_redirected_to admin_google_api_imports_url
      assert_equal "#{@business.name}: Google API取得を開始しました。BusinessMetricDailyへの反映は完了後に表示されます。", flash[:notice]
    end

    test "does not enqueue duplicate google api import while running" do
      GoogleApiImportRun.create!(
        business: @business,
        status: "running",
        source_types: %w[gsc ga4],
        started_at: Time.current
      )

      assert_no_difference("GoogleApiImportRun.count") do
        assert_no_enqueued_jobs do
          post admin_google_api_imports_url, params: { business_id: @business.id }
        end
      end

      assert_redirected_to admin_google_api_imports_url
      assert_equal "#{@business.name} はすでに取得中です。", flash[:alert]
    end

    test "does not enqueue google api import when google credential needs reauthentication" do
      @credential.update!(refresh_token: nil, access_token: nil, connected_at: nil)

      assert_no_difference("GoogleApiImportRun.count") do
        assert_no_enqueued_jobs do
          post admin_google_api_imports_url, params: { business_id: @business.id }
        end
      end

      assert_redirected_to admin_google_api_imports_url
      assert_equal "Google OAuth Clientが変更されています。Google認証画面で再認証してください。", flash[:alert]
    end
  end
end
