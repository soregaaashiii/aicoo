module Aicoo
  module Lovable
    class PipelineDiagnostic
      Row = Data.define(
        :business_id,
        :business_name,
        :connected,
        :connection_mode,
        :prompt_generated,
        :send_success,
        :preview_acquired,
        :version_saved,
        :last_sent_at,
        :preview_url,
        :version_count,
        :revision_count,
        :publication_status,
        :deploy_status,
        :learning_status,
        :last_error,
        :project_id
      )
      Result = Data.define(:configuration, :probe_status, :probe_error, :rows, :summary)

      def initialize(probe: false, client: McpClient.new, configuration: Configuration.new)
        @probe = probe
        @client = client
        @configuration = configuration
      end

      def call
        probe_status, probe_error = probe_connection
        rows = business_ids.map { |business_id| row_for(Business.find_by(id: business_id)) }.compact
        Result.new(
          configuration: configuration.diagnostic_snapshot,
          probe_status:,
          probe_error:,
          rows:,
          summary: {
            "business_count" => rows.size,
            "version_count" => rows.sum(&:version_count),
            "preview_ready_count" => rows.count { |row| row.preview_url.present? },
            "published_count" => rows.count { |row| row.publication_status == "published" },
            "failed_count" => rows.count { |row| row.last_error.present? }
          }
        )
      end

      private

      attr_reader :probe, :client, :configuration

      def probe_connection
        return [ configuration.configured? ? "configured_not_probed" : "build_url_fallback", nil ] unless probe
        return [ "build_url_fallback", "Lovable MCP OAuth tokenが未設定です。" ] unless client.configured?

        client.probe
        [ "connected", nil ]
      rescue StandardError => e
        [ "failed", e.message ]
      end

      def business_ids
        AicooLabGenerationRun.where(generation_type: "lp_generation").recent.filter_map do |run|
          run.metadata.to_h["business_id"].to_i if run.metadata.to_h["pipeline"] == "lovable"
        end.uniq
      end

      def row_for(business)
        return unless business

        repository = VersionRepository.new(business:)
        versions = repository.all
        latest = repository.latest
        current = repository.current
        publication = repository.published&.metadata.to_h&.fetch("publication", {}) || current&.metadata.to_h&.fetch("publication", {}) || {}
        learning = repository.published&.metadata.to_h&.fetch("learning", {}) || {}
        Row.new(
          business_id: business.id,
          business_name: business.name,
          connected: configuration.configured?,
          connection_mode: latest&.metadata.to_h&.dig("connection_mode") || configuration.connection_mode,
          prompt_generated: latest&.prompt.present?,
          send_success: latest&.status == "succeeded",
          preview_acquired: current&.metadata.to_h&.dig("preview_url").present?,
          version_saved: versions.any?,
          last_sent_at: latest&.started_at,
          preview_url: current&.metadata.to_h&.dig("preview_url"),
          version_count: versions.count,
          revision_count: versions.count { |run| run.metadata.to_h["request_type"] == "revision" },
          publication_status: publication["status"].presence || "not_requested",
          deploy_status: publication["deploy_status"].presence || "not_started",
          learning_status: learning["measurement_status"].presence || "not_started",
          last_error: latest&.error_message,
          project_id: current&.metadata.to_h&.dig("project_id")
        )
      end
    end
  end
end
