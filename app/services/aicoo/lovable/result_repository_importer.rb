require "base64"
require "digest"

module Aicoo
  module Lovable
    class ResultRepositoryImporter
      Result = Data.define(:generation_run, :landing_page, :commit_sha, :cloudflare_url, :idempotent)

      def initialize(
        source_client_class: Aicoo::CloudflarePages::GithubRepositoryClient,
        builder_class: StaticArtifactBuilder,
        validator_class: StaticArtifactValidator,
        publisher: Aicoo::CloudflarePages::LandingPagePublisher.new,
        configuration: Aicoo::CloudflarePages::Configuration.new
      )
        @source_client_class = source_client_class
        @builder_class = builder_class
        @validator_class = validator_class
        @publisher = publisher
        @configuration = configuration
      end

      def call(generation_run:)
        metadata = generation_run.metadata.to_h.deep_stringify_keys
        landing_page = BusinessPrototype.find(metadata.fetch("landing_page_prototype_id"))
        business = landing_page.business
        validate!(generation_run, landing_page, metadata)
        stamp!(generation_run, "lovable_result_waiting", "result_fetch_started_at")
        source_client = source_client_class.new(
          repository_url: metadata.fetch("lovable_result_repository"),
          branch: metadata["lovable_result_branch"].presence || "main",
          token: configuration.github_token
        )
        snapshot = source_client.snapshot!
        if committed_for_current_result?(metadata, snapshot.commit_sha)
          return Result.new(
            generation_run:,
            landing_page:,
            commit_sha: metadata.dig("publication", "commit_sha"),
            cloudflare_url: metadata.dig("publication", "production_url"),
            idempotent: true
          )
        end
        if metadata["lovable_last_synced_commit_sha"] == snapshot.commit_sha && metadata["publication_files"].present?
          return publish!(generation_run, landing_page, snapshot.commit_sha)
        end

        stamp!(generation_run, "lovable_result_received", "lovable_result_received_at", {
          "lovable_last_synced_commit_sha" => snapshot.commit_sha
        })
        page_path = page_path_for(landing_page)
        stamp!(generation_run, "static_build_started", "static_build_started_at")
        build = builder_class.new(files: snapshot.files, page_path:).call
        validation = validator_class.new(
          files: build.files,
          page_path:,
          public_url: public_url_for(page_path),
          service_url: service_url_for(business),
          measurement_id: measurement_id_for(business)
        ).call
        serialized_files = serialize_files(validation.files)
        digest = Digest::SHA256.hexdigest(serialized_files.to_json)
        generation_run.update!(
          metadata: generation_run.metadata.to_h.merge(
            "pipeline_status" => "github_commit_waiting",
            "lovable_status" => "result_received",
            "lovable_last_synced_commit_sha" => snapshot.commit_sha,
            "lovable_last_sync_at" => Time.current.iso8601,
            "static_build_status" => "succeeded",
            "static_build_type" => build.build_type,
            "static_build_warnings" => build.warnings,
            "static_validation_status" => "succeeded",
            "static_validation_warnings" => validation.warnings,
            "publication_files" => serialized_files,
            "publication_files_sha256" => digest,
            "static_validation_completed_at" => Time.current.iso8601,
            "lovable_error_code" => nil,
            "lovable_error_message" => nil
          )
        )
        publish!(generation_run, landing_page, snapshot.commit_sha)
      rescue StaticArtifactBuilder::UnsafeBuild => e
        mark_waiting_manual_fix(generation_run, "static_build_failed", e)
        raise
      rescue StaticArtifactValidator::InvalidArtifact => e
        mark_waiting_manual_fix(generation_run, "static_validation_failed", e)
        raise
      rescue StandardError => e
        mark_retryable_failure(generation_run, e)
        raise
      end

      private

      attr_reader :source_client_class, :builder_class, :validator_class, :publisher, :configuration

      def validate!(run, landing_page, metadata)
        raise ArgumentError, "Lovable LP生成Runではありません。" unless metadata["pipeline"] == "lovable"
        raise ArgumentError, "Lovable生成結果Repositoryを登録してください。" if metadata["lovable_result_repository"].blank?
        unless landing_page.external_landing_page? && landing_page.business_id == metadata["business_id"].to_i
          raise ArgumentError, "Lovable生成RunとLPが一致しません。"
        end
        task = AutoRevisionTask.find_by(id: metadata["auto_revision_task_id"])
        raise ArgumentError, "Owner承認前のため成果物を取得できません。" unless task&.approved_at.present?
        raise ArgumentError, "公開済みVersionです。" if run.metadata.to_h.dig("publication", "published") == true
      end

      def publish!(run, landing_page, source_commit_sha)
        stamp!(run, "github_commit_waiting", "github_commit_started_at")
        result = publisher.publish!(landing_page:, generation_run: run)
        run.reload.update!(metadata: run.metadata.to_h.merge(
          "pipeline_status" => "cloudflare_deploying",
          "lovable_status" => "completed",
          "lovable_last_synced_commit_sha" => source_commit_sha,
          "github_commit_sha" => result.commit_sha,
          "cloudflare_url" => result.cloudflare_url,
          "lovable_completed_at" => run.metadata.to_h["lovable_completed_at"] || Time.current.iso8601
        ))
        Result.new(
          generation_run: run,
          landing_page:,
          commit_sha: result.commit_sha,
          cloudflare_url: result.cloudflare_url,
          idempotent: false
        )
      end

      def committed_for_current_result?(metadata, source_commit_sha)
        metadata.dig("publication", "commit_sha").present? &&
          metadata["lovable_last_synced_commit_sha"] == source_commit_sha &&
          metadata["publication_files_sha256"].present?
      end

      def serialize_files(values)
        values.to_h.transform_values do |content|
          { "content" => Base64.strict_encode64(content.to_s.b), "encoding" => "base64" }
        end
      end

      def stamp!(run, status, timestamp_key, extra = {})
        run.update!(metadata: run.metadata.to_h.merge(
          "pipeline_status" => status,
          timestamp_key => Time.current.iso8601
        ).merge(extra))
      end

      def mark_waiting_manual_fix(run, error_code, error)
        return unless run&.persisted?

        run.update!(
          error_message: error.message,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "waiting_manual_fix",
            "lovable_status" => "waiting_manual_fix",
            "lovable_error_code" => error_code,
            "lovable_error_message" => error.message,
            "lovable_last_error_at" => Time.current.iso8601
          )
        )
      end

      def mark_retryable_failure(run, error)
        return unless run&.persisted?

        code = github_permission_error?(error.message) ? "github_permission_error" : "result_import_failed"
        current = run.metadata.to_h["pipeline_status"]
        status = current == "github_commit_waiting" ? "github_commit_waiting" : "lovable_result_waiting"
        run.update!(
          error_message: error.message,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => status,
            "lovable_error_code" => code,
            "lovable_error_message" => error.message,
            "lovable_last_error_at" => Time.current.iso8601
          )
        )
      end

      def github_permission_error?(message)
        message.to_s.include?("AICOO_GITHUB_TOKEN") || message.to_s.include?("GitHub Repository")
      end

      def page_path_for(landing_page)
        path = landing_page.landing_page_ga4_path.presence
        path ||= "/#{landing_page.metadata.to_h['github_path'].to_s.delete_prefix('public/').delete_suffix('/')}" if landing_page.metadata.to_h["github_path"].present?
        raise ArgumentError, "LP固有page_pathが未設定です。" if path.blank?

        "/#{path.to_s.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}"
      end

      def public_url_for(page_path)
        "#{configuration.production_url.delete_suffix('/')}#{page_path}/"
      end

      def service_url_for(business)
        business.business_execution_profile&.production_url.presence ||
          business.business_services.where.not(url: [ nil, "" ]).order(:id).pick(:url)
      end

      def measurement_id_for(business)
        business.metadata.to_h["lp_ga4_measurement_id"].presence ||
          Aicoo::LpIntegration::Overview.new(business).ga4_measurement_id
      end
    end
  end
end
