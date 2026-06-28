require "test_helper"

module AicooAnalytics
  class BusinessGoogleApiImportJobTest < ActiveJob::TestCase
    setup do
      @business = businesses(:suelog)
      BusinessMetricDaily.delete_all
      @original_new = BusinessGoogleApiMetricImporter.method(:new)
    end

    teardown do
      original_new = @original_new
      BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |*args, **kwargs, &block|
        original_new.call(*args, **kwargs, &block)
      end
    end

    test "marks run successful and updates business metrics" do
      fake_importer_class = Class.new do
        Result = Data.define(:metric_count, :imported_source_labels, :start_date, :end_date)

        def initialize(business:, **_kwargs)
          @business = business
        end

        def call
          BusinessMetricDaily.create!(
            business: @business,
            recorded_on: Date.current - 1.day,
            sessions: 12,
            clicks: 3
          )
          Result.new(1, %w[GSC GA4], Date.current - 1.day, Date.current - 1.day)
        end
      end
      BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |business:, **kwargs|
        fake_importer_class.new(business:, **kwargs)
      end
      run = GoogleApiImportRun.create!(
        business: @business,
        status: "queued",
        source_types: %w[gsc ga4],
        fetched_days: 3
      )

      assert_difference("BusinessMetricDaily.count", 1) do
        BusinessGoogleApiImportJob.perform_now(run.id)
      end

      run.reload
      assert_equal "success", run.status
      assert run.started_at.present?
      assert run.finished_at.present?
      assert_equal 1, run.updated_metric_count
      assert_equal [ "GSC", "GA4" ], run.metadata["imported_source_labels"]
    end

    test "marks run failed when importer raises" do
      BusinessGoogleApiMetricImporter.define_singleton_method(:new) do |business:, **_kwargs|
        Class.new do
          def call
            raise BusinessGoogleApiMetricImporter::Error, "Refresh Tokenがありません"
          end
        end.new
      end
      run = GoogleApiImportRun.create!(
        business: @business,
        status: "queued",
        source_types: %w[gsc],
        fetched_days: 1
      )

      BusinessGoogleApiImportJob.perform_now(run.id)

      run.reload
      assert_equal "failed", run.status
      assert run.started_at.present?
      assert run.finished_at.present?
      assert_equal "Refresh Tokenがありません", run.error_message
    end
  end
end
