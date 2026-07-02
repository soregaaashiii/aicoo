module Admin
  class TrafficChannelsController < ApplicationController
    def show
      load_traffic_channel_center
    end

    def update_channel
      profile = DataSourceCostProfile.find_or_initialize_by(source_key: params[:channel_key].to_s)
      profile.enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:traffic_channel, :enabled))
      profile.save!
      redirect_to admin_traffic_channels_path(anchor: "traffic-channel-settings"), notice: "#{profile.name}の設定を保存しました。"
    end

    def update_business_channel
      business = Business.real_businesses.find(params[:business_id])
      setting = BusinessDataSourceSetting.find_or_initialize_by(business:, source_key: params[:channel_key].to_s)
      setting.enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:traffic_channel, :enabled))
      setting.connection_status = setting.enabled? ? "linked" : "unlinked"
      setting.save!
      redirect_to admin_traffic_channels_path(anchor: "traffic-business-settings"), notice: "#{business.name}のチャネル設定を保存しました。"
    end

    def create_action_candidate
      business = Business.real_businesses.find(params[:business_id])
      candidate = Aicoo::TrafficChannels::ActionCandidateGenerator.call(
        business:,
        channel_key: params[:channel_key]
      )
      redirect_to action_candidate_path(candidate), notice: "Traffic Channel由来の改善候補を作成しました。"
    rescue ArgumentError => e
      redirect_to admin_traffic_channels_path, alert: e.message
    end

    private

    def load_traffic_channel_center
      DataSourceCostProfile.ensure_defaults!
      @channels = Aicoo::TrafficChannels::Registry.channels
      @channel_keys = Aicoo::TrafficChannels::Registry.keys
      @summary = Aicoo::TrafficChannels::Summary.call
      @serp_summary = Aicoo::Serp::Summary.call
      @profiles_by_key = DataSourceCostProfile.where(source_key: @channel_keys).index_by(&:source_key)
      @businesses = Business.real_businesses.includes(:business_data_source_settings).order(:name)
      @business_settings = BusinessDataSourceSetting.where(source_key: @channel_keys, business: @businesses).index_by { |setting| [ setting.business_id, setting.source_key ] }
      @today_runs_by_channel = TrafficChannelRun.today.group(:channel_key).count
      @today_failed_runs_by_channel = TrafficChannelRun.today.failed.group(:channel_key).count
      @last_runs_by_channel = TrafficChannelRun.recent.where(channel_key: @channel_keys).each_with_object({}) do |run, rows|
        rows[run.channel_key] ||= run
      end
      @serp_channel_stats = serp_channel_stats
      @recent_runs = TrafficChannelRun.includes(:business).recent.limit(30)
      @performance_rows = Aicoo::TrafficChannels::PerformanceTable.call
    end

    def serp_channel_stats
      today_runs = SerpRun.today
      latest_run = SerpRun.recent.first
      problem_run_count = today_runs.where(status: %w[failed partial_failed]).count
      failed_query_count = today_runs.sum(:failure_count)
      scheduler_enabled = Aicoo::Serp::Scheduler.enabled?
      last_executor = latest_run&.executed_by

      {
        today_count: today_runs.sum(:query_count),
        error_count: problem_run_count + failed_query_count,
        failed_query_count:,
        problem_run_count:,
        latest_run:,
        usage_label: [
          scheduler_enabled ? "Scheduler ON" : "Scheduler OFF",
          last_executor ? "latest: #{last_executor}" : nil
        ].compact.join(" / ")
      }
    end
  end
end
