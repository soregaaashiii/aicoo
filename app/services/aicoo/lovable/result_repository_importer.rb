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
        configuration: Aicoo::CloudflarePages::Configuration.new,
        page_path_assigner_class: Aicoo::LpIntegration::LandingPagePagePathAssigner
      )
        @source_client_class = source_client_class
        @builder_class = builder_class
        @validator_class = validator_class
        @publisher = publisher
        @configuration = configuration
        @page_path_assigner_class = page_path_assigner_class
      end

      def call(generation_run:, source_commit_sha: nil)
        metadata = generation_run.metadata.to_h.deep_stringify_keys
        landing_page = BusinessPrototype.find(metadata.fetch("landing_page_prototype_id"))
        business = landing_page.business
        validate!(generation_run, landing_page, metadata)
        fetch_started_at = Time.current
        stamp!(generation_run, "artifact_fetching", "result_fetch_started_at")
        source_client = source_client_class.new(
          repository_url: metadata.fetch("lovable_result_repository"),
          branch: metadata["lovable_result_branch"].presence || "main",
          token: configuration.github_token
        )
        snapshot = source_commit_sha.present? ? source_client.snapshot!(commit_sha: source_commit_sha) : source_client.snapshot!
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

        fetch_completed_at = Time.current
        artifact_diagnostics = artifact_diagnostics_for(snapshot)
        stamp!(generation_run, "lovable_result_received", "lovable_result_received_at", {
          "lovable_last_synced_commit_sha" => snapshot.commit_sha,
          "artifact_fetch_completed_at" => fetch_completed_at.iso8601,
          "artifact_fetch_duration_ms" => elapsed_ms(fetch_started_at, fetch_completed_at)
        }.merge(source_commit_metadata(snapshot)).merge(artifact_diagnostics))
        page_path, page_path_assignment = page_path_for(landing_page)
        build_started_at = Time.current
        stamp!(
          generation_run,
          "static_building",
          "static_build_started_at",
          page_path_generation_metadata(page_path, page_path_assignment)
        )
        build = builder_class.new(
          files: snapshot.files,
          page_path:,
          output_directory: metadata["static_build_output_directory"]
        ).call
        build_completed_at = Time.current
        generation_run.update!(
          metadata: generation_run.metadata.to_h.merge(
            static_build_metadata(
              build,
              build_started_at:,
              build_completed_at:
            )
          )
        )
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
          generated_count: 1,
          metadata: generation_run.metadata.to_h.merge(
            "pipeline_status" => "github_commit_waiting",
            "lovable_status" => "result_received",
            "lovable_last_synced_commit_sha" => snapshot.commit_sha,
            "lovable_last_sync_at" => Time.current.iso8601,
            "static_build_generated_file_count" => validation.files.size,
            "static_build_generated_files" => validation.files.keys.sort.first(200),
            "static_validation_status" => "succeeded",
            "static_validation_warnings" => validation.warnings,
            "publication_files" => serialized_files,
            "publication_files_sha256" => digest,
            "static_validation_completed_at" => build_completed_at.iso8601,
            "pipeline_recovery_status" => nil,
            "pipeline_next_retry_at" => nil,
            "lovable_error_code" => nil,
            "lovable_error_message" => nil
          )
        )
        publish!(generation_run, landing_page, snapshot.commit_sha)
      rescue StaticArtifactBuilder::UnsafeBuild => e
        mark_waiting_manual_fix(generation_run, e.code, e, static_build_failure_metadata(e))
        raise
      rescue StaticArtifactValidator::InvalidArtifact => e
        mark_waiting_manual_fix(generation_run, "static_validation_failed", e)
        raise
      rescue StandardError => e
        mark_retryable_failure(generation_run, e)
        raise
      end

      private

      attr_reader :source_client_class, :builder_class, :validator_class, :publisher, :configuration,
        :page_path_assigner_class

      def artifact_diagnostics_for(snapshot)
        paths = snapshot.files.keys
        counts = paths.each_with_object(Hash.new(0)) do |path, values|
          values[file_category(path)] += 1
        end
        {
          "artifact_fetched_file_count" => paths.size,
          "artifact_file_counts" => counts,
          "artifact_excluded_file_count" => snapshot.excluded_paths.size,
          "artifact_excluded_paths" => snapshot.excluded_paths.first(200),
          "artifact_build_targets" => paths.select { |path| build_target_path?(path) }.sort.first(200)
        }
      end

      def source_commit_metadata(snapshot)
        {
          "source_commit_sha" => snapshot.commit_sha,
          "source_commit_url" => snapshot.commit_url,
          "source_commit_at" => snapshot.committed_at,
          "source_commit_author" => snapshot.author,
          "source_changed_file_count" => snapshot.changed_paths.size,
          "source_changed_paths" => snapshot.changed_paths.first(200)
        }.compact
      end

      def file_category(path)
        extension = File.extname(path.to_s).downcase
        return "html" if extension.in?(%w[.html .htm])
        return "css" if extension == ".css"
        return "javascript" if extension.in?(%w[.js .mjs .cjs .jsx .ts .tsx])
        return "images" if extension.in?(%w[.png .jpg .jpeg .gif .webp .svg .avif .ico])

        "other"
      end

      def build_target_path?(path)
        File.basename(path.to_s).in?(%w[
          index.html package.json package-lock.json pnpm-lock.yaml yarn.lock
        ]) || path.to_s.start_with?("dist/", "build/", "out/")
      end

      def build_log_for(build)
        [
          "Build type: #{build.build_type}",
          ("Framework: #{build.framework}" if build.framework.present?),
          ("Package manager: #{build.package_manager}" if build.package_manager.present?),
          ("Commands: #{build.commands.join(' / ')}" if build.commands.present?),
          ("Output directory: #{build.output_directory}" if build.output_directory.present?),
          ("Exit code: #{build.build_exit_code}" unless build.build_exit_code.nil?),
          "Static build succeeded",
          *Array(build.warnings)
        ].compact
      end

      def static_build_metadata(build, build_started_at:, build_completed_at:)
        {
          "static_build_status" => "succeeded",
          "static_build_type" => build.build_type,
          "static_build_warnings" => build.warnings,
          "static_build_framework" => build.framework,
          "static_build_package_manager" => build.package_manager,
          "static_build_commands" => build.commands,
          "static_build_output_directory" => build.output_directory,
          "static_build_output_candidates" => build.output_candidates,
          "static_build_post_build_files" => build.post_build_files,
          "static_build_temporary_config_adjustments" => build.temporary_config_adjustments,
          "static_build_lockfile_generated" => build.lockfile_generated,
          "static_build_lockfile_generated_at" => build.lockfile_generated ? build_completed_at.iso8601 : nil,
          "static_build_lockfile_message" => build.lockfile_generated ?
            "package-lock.jsonがなかったため一時生成しました" : nil,
          "static_build_command_started_at" => build.build_started_at,
          "static_build_command_finished_at" => build.build_finished_at,
          "static_build_duration_ms" => build.build_duration_ms ||
            elapsed_ms(build_started_at, build_completed_at),
          "static_build_stdout" => build.build_stdout,
          "static_build_stderr" => build.build_stderr,
          "static_build_exit_code" => build.build_exit_code,
          "static_build_log" => build_log_for(build)
        }
      end

      def elapsed_ms(started_at, finished_at)
        ((finished_at - started_at) * 1_000).round
      end

      def validate!(run, landing_page, metadata)
        raise ArgumentError, "Lovable LP生成Runではありません。" unless metadata["pipeline"] == "lovable"
        raise ArgumentError, "Lovable生成結果Repositoryを登録してください。" if metadata["lovable_result_repository"].blank?
        unless landing_page.external_landing_page? && landing_page.business_id == metadata["business_id"].to_i
          raise ArgumentError, "Lovable生成RunとLPが一致しません。"
        end
        unless trusted_repository_import?(landing_page, metadata)
          task = AutoRevisionTask.find_by(id: metadata["auto_revision_task_id"])
          raise ArgumentError, "Owner承認前のため成果物を取得できません。" unless task&.approved_at.present?
        end
        raise ArgumentError, "公開済みVersionです。" if run.metadata.to_h.dig("publication", "published") == true
      end

      def trusted_repository_import?(landing_page, metadata)
        return false unless metadata["repository_import"] == true

        saved_repository = GithubRepositoryIdentity.normalize(landing_page.landing_page_repository_url)
        run_repository = GithubRepositoryIdentity.normalize(metadata["lovable_result_repository"])
        saved_branch = landing_page.landing_page_branch
        run_branch = metadata["lovable_result_branch"].presence || "main"
        saved_repository.present? &&
          saved_repository == run_repository &&
          saved_branch == run_branch
      end

      def publish!(run, landing_page, source_commit_sha)
        stamp!(run, "github_commit_waiting", "github_commit_started_at")
        result = publisher.publish!(landing_page:, generation_run: run)
        run.reload.update!(metadata: run.metadata.to_h.merge(
          "pipeline_status" => "cloudflare_waiting",
          "lovable_status" => "completed",
          "lovable_last_synced_commit_sha" => source_commit_sha,
          "github_commit_sha" => result.commit_sha,
          "cloudflare_url" => result.cloudflare_url,
          "preview_url" => result.cloudflare_url,
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

      def mark_waiting_manual_fix(run, error_code, error, extra_metadata = {})
        return unless run&.persisted?

        run.update!(
          error_message: error.message,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "waiting_manual_fix",
            "lovable_status" => "waiting_manual_fix",
            "lovable_error_code" => error_code,
            "lovable_error_message" => error.message,
            "lovable_last_error_at" => Time.current.iso8601
          ).merge(extra_metadata)
        )
      end

      def static_build_failure_metadata(error)
        details = error.details.to_h.deep_stringify_keys
        lockfile_generated = details["lockfile_generated"] == true
        {
          "static_build_status" => "failed",
          "static_build_failure_code" => error.code,
          "static_build_framework" => details["framework"],
          "static_build_package_manager" => details["package_manager"],
          "static_build_commands" => details["commands"],
          "static_build_output_directory" => details["output_directory"],
          "static_build_output_candidates" => details["output_candidates"],
          "static_build_post_build_files" => details["post_build_files"],
          "static_build_temporary_config_adjustments" => details["temporary_config_adjustments"],
          "static_build_lockfile_generated" => lockfile_generated,
          "static_build_lockfile_generated_at" => lockfile_generated ? Time.current.iso8601 : nil,
          "static_build_lockfile_message" => lockfile_generated ?
            "package-lock.jsonがなかったため一時生成しました" : nil,
          "static_build_command_started_at" => details["build_started_at"],
          "static_build_command_finished_at" => details["build_finished_at"],
          "static_build_duration_ms" => details["build_duration_ms"],
          "static_build_stdout" => details["build_stdout"],
          "static_build_stderr" => details["build_stderr"],
          "static_build_exit_code" => details["build_exit_code"]
        }
      end

      def mark_retryable_failure(run, error)
        return unless run&.persisted?

        current = run.metadata.to_h["pipeline_status"]
        code = if github_permission_error?(error.message)
          "github_permission_error"
        elsif current == "artifact_fetching"
          "artifact_fetch_failed"
        else
          "result_import_failed"
        end
        status = current == "github_commit_waiting" ? "github_commit_waiting" : "github_webhook_waiting"
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
        assignment = page_path_assigner_class.new(landing_page:).call
        path = assignment.page_path

        [ "/#{path.to_s.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}", assignment ]
      end

      def page_path_generation_metadata(page_path, assignment)
        return {} unless assignment.generated

        {
          "page_path" => page_path,
          "page_path_generated_at" => Time.current.iso8601,
          "page_path_generation_source" => assignment.source.to_s,
          "page_path_generation_message" => "page_pathを自動生成しました"
        }
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
