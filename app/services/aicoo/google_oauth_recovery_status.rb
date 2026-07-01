module Aicoo
  class GoogleOauthRecoveryStatus
    SourceStatus = Data.define(
      :source_key,
      :label,
      :status,
      :last_success_at,
      :last_error,
      :latest_run,
      :credential
    ) do
      def connected?
        status == "connected"
      end

      def invalid_grant?
        status == "invalid_grant"
      end
    end

    GOOGLE_SOURCES = {
      "ga4" => "GA4",
      "gsc" => "GSC"
    }.freeze

    def initialize(credential: AicooGoogleCredential.default)
      @credential = credential&.reload
    end

    def call
      GOOGLE_SOURCES.map do |source_key, label|
        SourceStatus.new(
          source_key:,
          label:,
          status: status_for(source_key),
          last_success_at: last_success_run_for(source_key)&.finished_at,
          last_error: latest_failed_run_for(source_key)&.error_message,
          latest_run: latest_run_for(source_key),
          credential:
        )
      end
    end

    private

    attr_reader :credential

    def status_for(source_key)
      return "missing" unless credential&.client_id.present? && credential&.client_secret.present?
      return "missing" if credential.refresh_token.blank?
      return "invalid_grant" if latest_failed_run_for(source_key)&.error_message.to_s.match?(/invalid_grant|expired or revoked/i)
      return "expired" if credential.token_expired?

      "connected"
    end

    def latest_run_for(source_key)
      runs_for(source_key).first
    end

    def latest_failed_run_for(source_key)
      runs_for(source_key).find { |run| run.status == "failed" }
    end

    def last_success_run_for(source_key)
      runs_for(source_key).find { |run| run.status == "success" }
    end

    def runs_for(source_key)
      @runs_for ||= {}
      @runs_for[source_key] ||= AnalyticsFetchRun
        .joins(:analytics_source_setting)
        .where(analytics_source_settings: { source_type: source_key })
        .order(created_at: :desc)
        .limit(20)
        .to_a
    end
  end
end
