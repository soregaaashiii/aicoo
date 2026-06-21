module AicooAnalytics
  class FetchRunner
    def initialize(setting)
      @setting = setting
    end

    def call
      run = setting.analytics_fetch_runs.create!(status: "running", started_at: Time.current)

      result = fetcher.call
      run.update!(
        status: "success",
        finished_at: Time.current,
        data_import_id: result.data_import.id,
        snapshot_count: result.pipeline_result.snapshot_count,
        updated_neglect_loss_count: result.pipeline_result.updated_neglect_loss_count,
        error_message: nil
      )
      run
    rescue StandardError => e
      run ||= setting.analytics_fetch_runs.create!(status: "running", started_at: Time.current)
      run.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: error_message(e)
      )
      run
    end

    private

    attr_reader :setting

    def fetcher
      case setting.source_type
      when "gsc"
        GscFetcher.new(setting)
      when "ga4"
        Ga4Fetcher.new(setting)
      end
    end

    def error_message(error)
      return error.message if error.message.include?("client_id_source=")
      return error.message unless error.is_a?(GoogleOauthClient::Error)

      "#{error.message} #{GoogleAccessToken.new(setting).credential_source_summary}"
    end
  end
end
