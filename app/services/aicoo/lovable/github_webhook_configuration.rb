module Aicoo
  module Lovable
    class GithubWebhookConfiguration
      PROFILE_KEY = "github_lovable_webhook".freeze
      SECRET_ENV_KEYS = %w[AICOO_GITHUB_WEBHOOK_SECRET GITHUB_WEBHOOK_SECRET].freeze

      def initialize(env: ENV, profile: nil)
        @env = env
        @profile = profile
      end

      def secret
        SECRET_ENV_KEYS.filter_map { |key| env[key].presence }.first || profile&.credentials.to_h["secret"].presence
      end

      def configured?
        secret.present?
      end

      def diagnostics
        profile&.metadata.to_h.fetch("webhook", {})
      end

      def update_secret!(value)
        record = persisted_profile
        credentials = record.credentials.to_h
        credentials["secret"] = value if value.present?
        record.update!(
          enabled: true,
          execution_mode: "auto",
          metadata: record.metadata.to_h.merge("credentials" => credentials)
        )
        record
      end

      def record!(status:, failure: false, attributes: {})
        now = Time.current
        record = persisted_profile
        record.with_lock do
          webhook = record.metadata.to_h.fetch("webhook", {}).merge(
            "last_received_at" => now.iso8601,
            "last_status" => status.to_s,
            "received_count" => record.metadata.to_h.dig("webhook", "received_count").to_i + 1
          ).merge(attributes.to_h.deep_stringify_keys.compact)
          if failure
            webhook["failure_count"] = webhook["failure_count"].to_i + 1
            webhook["last_failure_at"] = now.iso8601
          end
          webhook["last_push_at"] = now.iso8601 if status.to_s.in?(%w[accepted duplicate])
          record.update!(
            last_run_at: now,
            last_error: failure ? webhook["error"].presence || status.to_s : nil,
            metadata: record.metadata.to_h.merge("webhook" => webhook)
          )
        end
        record
      end

      private

      attr_reader :env

      def profile
        @profile ||= DataSourceCostProfile.find_by(source_key: PROFILE_KEY)
      end

      def persisted_profile
        @profile ||= DataSourceCostProfile.find_or_create_by!(source_key: PROFILE_KEY) do |record|
          record.name = "Lovable GitHub Webhook"
          record.execution_mode = "auto"
          record.enabled = true
        end
        @profile.save! if @profile.new_record?
        @profile
      end
    end
  end
end
