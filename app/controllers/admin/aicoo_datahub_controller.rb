module Admin
  class AicooDatahubController < ApplicationController
    def show
      @summary = Summary.new
      @recent_snapshots = AicooDataSnapshot.recent.limit(20)
      @collection_runs = AicooDataHubCollectionRun.recent.limit(20)
      @scoring_candidates = AicooDataHub::ScoringCandidateFinder.new.call
    end

    def collect_landing_pages
      result = AicooDataHub::SnapshotCollector.new.collect_landing_pages

      redirect_to admin_aicoo_datahub_path, notice: "LP実績データを#{result.count}件作成しました"
    end

    def collect_revenue
      result = AicooDataHub::SnapshotCollector.new.collect_revenue

      redirect_to admin_aicoo_datahub_path, notice: "収益実績データを#{result.count}件作成しました"
    end

    def collect_data_imports
      result = AicooDataHub::SnapshotCollector.new.collect_data_imports

      redirect_to admin_aicoo_datahub_path, notice: "取込データを#{result.count}件作成しました"
    end

    def collect_all
      result = AicooDataHub::SnapshotCollector.new.collect_all

      redirect_to admin_aicoo_datahub_path, notice: "全実績データを#{result.count}件作成しました"
    end

    def run_daily_collection
      run = AicooDataHub::DailyCollector.new.call

      redirect_to admin_aicoo_datahub_path, notice: "自動収集を実行しました。実績データを#{run.snapshot_count}件作成しました"
    rescue StandardError => e
      redirect_to admin_aicoo_datahub_path, alert: "自動収集に失敗しました: #{e.message}"
    end

    Summary = Data.define do
      def total_count
        AicooDataSnapshot.count
      end

      def today_count
        AicooDataSnapshot.today.count
      end

      def ga4_count
        source_count("ga4")
      end

      def gsc_count
        source_count("gsc")
      end

      def landing_page_count
        source_count("landing_page")
      end

      def revenue_execution_count
        source_count("revenue_execution")
      end

      private

      def source_count(source_type)
        AicooDataSnapshot.where(source_type:).count
      end
    end
  end
end
