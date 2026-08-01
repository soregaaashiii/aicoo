require "uri"

module Aicoo
  module CloudflarePages
    class LandingPagePublisher
      Result = Data.define(:landing_page, :commit_sha, :commit_url, :github_path, :cloudflare_url, :asset_source, :deleted)

      def initialize(configuration: Configuration.new, client: nil, bundle_builder_class: LandingPageAssetBundle)
        @configuration = configuration
        @client = client || GithubRepositoryClient.new(
          repository_url: configuration.repository_url,
          branch: configuration.branch,
          token: configuration.github_token
        )
        @bundle_builder_class = bundle_builder_class
      end

      def publish!(landing_page:, generation_run: nil, commit_message: nil)
        validate_landing_page!(landing_page)
        publication_configuration = configuration.for_business(landing_page.business)
        github_path = github_path_for(landing_page)
        ensure_path_is_available!(landing_page, github_path)
        bundle = bundle_builder_class.new(landing_page:, generation_run:).call
        files = bundle.files.to_h do |relative_path, content|
          [ "#{github_path.delete_suffix('/')}/#{relative_path}", content ]
        end
        push_started_at = Time.current
        result = client.commit!(
          files:,
          message: commit_message.presence || commit_message_for(generation_run)
        )
        page_path = page_path_for(landing_page, github_path)
        cloudflare_url = cloudflare_url_for(page_path, publication_configuration)
        now = Time.current
        push_duration_ms = ((now - push_started_at) * 1_000).round
        metadata = landing_page.metadata.to_h.merge(
          "lp_publication_repository_url" => configuration.repository_url,
          "lp_publication_branch" => configuration.branch,
          "github_path" => github_path,
          "github_commit_sha" => result.commit_sha,
          "github_commit_url" => result.commit_url,
          "last_push_at" => now.iso8601,
          "last_push_duration_ms" => push_duration_ms,
          "last_push_file_count" => result.changed_paths.size,
          "last_push_changed_paths" => result.changed_paths.first(200),
          "ga4_page_path" => page_path,
          "lp_url" => cloudflare_url,
          "gsc_url" => cloudflare_url,
          "cloudflare_url" => cloudflare_url,
          "cloudflare_project_name" => publication_configuration.project_name,
          "cloudflare_deploy_status" => "deploying",
          "sync_status" => "syncing",
          "planning_status" => "cloudflare_pending",
          "pipeline_stage" => "cloudflare_pending",
          "pipeline_stages" => Aicoo::LpIntegration::LandingPagePipelineState.build(current: "cloudflare_pending", approval_required: false),
          "asset_source" => bundle.source
        )
        landing_page.update!(metadata:)
        stamp_generation_run!(
          generation_run,
          landing_page,
          result,
          cloudflare_url,
          bundle.source,
          publication_configuration:,
          push_started_at:,
          pushed_at: now,
          push_duration_ms:
        )
        enqueue_verification(landing_page, result.commit_sha)
        Result.new(
          landing_page:,
          commit_sha: result.commit_sha,
          commit_url: result.commit_url,
          github_path:,
          cloudflare_url:,
          asset_source: bundle.source,
          deleted: false
        )
      end

      def delete!(landing_page:)
        validate_external_landing_page!(landing_page)
        github_path = landing_page.metadata.to_h["github_path"].presence
        return Result.new(landing_page:, commit_sha: nil, commit_url: nil, github_path: nil, cloudflare_url: landing_page.landing_page_url, asset_source: nil, deleted: true) unless github_path

        validate_publication_configuration!
        deleted_paths = client.paths_under(github_path)
        return Result.new(landing_page:, commit_sha: nil, commit_url: nil, github_path:, cloudflare_url: landing_page.landing_page_url, asset_source: nil, deleted: true) if deleted_paths.empty?

        result = client.commit!(
          files: {},
          deleted_paths:,
          message: "Delete LP: #{landing_page.landing_page_name}"
        )
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "github_commit_sha" => result.commit_sha,
          "github_commit_url" => result.commit_url,
          "last_push_at" => Time.current.iso8601,
          "cloudflare_deploy_status" => "deleting",
          "sync_status" => "syncing",
          "deleted_github_paths" => deleted_paths
        ))
        enqueue_verification(landing_page, result.commit_sha, deleted: true)
        Result.new(
          landing_page:,
          commit_sha: result.commit_sha,
          commit_url: result.commit_url,
          github_path:,
          cloudflare_url: landing_page.landing_page_url,
          asset_source: nil,
          deleted: true
        )
      end

      private

      attr_reader :configuration, :client, :bundle_builder_class

      def validate_landing_page!(landing_page)
        validate_external_landing_page!(landing_page)
        validate_publication_configuration!
      end

      def validate_external_landing_page!(landing_page)
        raise ArgumentError, "外部LPだけがCloudflare Pages公開対象です。" unless landing_page.external_landing_page?
      end

      def validate_publication_configuration!
        raise ArgumentError, "LP専用GitHub Repositoryを設定してください。" unless configuration.github_configured?
        return if configuration.repository_url.to_s.match?(%r{(?:github\.com[:/])[^/]+/aicoo-lp(?:\.git)?\z}i)

        raise ArgumentError, "LP公開先はaicoo-lp Repositoryに限定されています。"
      end

      def github_path_for(landing_page)
        existing = landing_page.metadata.to_h["github_path"].presence
        return normalize_github_path(existing) if existing

        page_path = landing_page.landing_page_ga4_path.presence || URI.parse(landing_page.landing_page_url.to_s).path.presence
        page_path = nil if page_path == "/"
        segments = page_path.to_s.split("/").filter_map { |segment| slug(segment) }
        segments = fallback_segments(landing_page) if segments.empty?
        normalize_github_path("public/#{segments.join('/')}/")
      rescue URI::InvalidURIError
        normalize_github_path("public/#{fallback_segments(landing_page).join('/')}/")
      end

      def normalize_github_path(value)
        path = value.to_s.tr("\\", "/").sub(%r{\A/+}, "")
        path = "public/#{path}" unless path.start_with?("public/")
        parts = path.split("/").reject(&:blank?)
        raise ArgumentError, "GitHub Pathが不正です。" if parts.include?("..") || parts.first != "public"

        "#{parts.join('/')}/"
      end

      def fallback_segments(landing_page)
        [
          slug(landing_page.business.name) || "business-#{landing_page.business_id}",
          slug(landing_page.business_campaign&.name) || "campaign-#{landing_page.business_campaign_id}",
          slug(landing_page.landing_page_name) || "lp-#{landing_page.id}"
        ]
      end

      def slug(value)
        normalized = value.to_s.downcase.strip
          .gsub(/[^a-z0-9]+/, "-")
          .gsub(/\A-+|-+\z/, "")
        normalized.presence
      end

      def ensure_path_is_available!(landing_page, github_path)
        conflict = BusinessPrototype.active.external_landing_pages.where.not(id: landing_page.id).find do |candidate|
          candidate.metadata.to_h["github_path"].to_s == github_path
        end
        return unless conflict

        raise ArgumentError, "GitHub PathはLP ##{conflict.id}が使用中です。A/B Variantは別pathで作成してください。"
      end

      def page_path_for(landing_page, github_path)
        path = landing_page.landing_page_ga4_path.to_s
        return path if path.present? && path != "/"

        "/#{github_path.delete_prefix('public/').delete_suffix('/')}"
      end

      def cloudflare_url_for(page_path, publication_configuration)
        "#{publication_configuration.production_url.delete_suffix('/')}#{page_path.sub(%r{/\z}, '')}/"
      end

      def commit_message_for(generation_run)
        case generation_run&.metadata.to_h&.dig("request_type")
        when "revision", "retry", "restore" then "Improve LP"
        else "Generate LP"
        end
      end

      def stamp_generation_run!(
        generation_run,
        landing_page,
        result,
        cloudflare_url,
        asset_source,
        publication_configuration:,
        push_started_at:,
        pushed_at:,
        push_duration_ms:
      )
        return unless generation_run

        publication = generation_run.metadata.to_h.fetch("publication", {}).merge(
          "status" => "github_pushed",
          "published" => false,
          "landing_page_prototype_id" => landing_page.id,
          "repository_url" => publication_configuration.repository_url,
          "branch" => publication_configuration.branch,
          "github_path" => landing_page.metadata.to_h["github_path"],
          "commit_sha" => result.commit_sha,
          "commit_url" => result.commit_url,
          "production_url" => cloudflare_url,
          "asset_source" => asset_source,
          "push_started_at" => push_started_at.iso8601,
          "pushed_at" => pushed_at.iso8601,
          "push_duration_ms" => push_duration_ms,
          "changed_file_count" => result.changed_paths.size,
          "changed_paths" => result.changed_paths.first(200)
        )
        generation_run.update!(metadata: generation_run.metadata.to_h.merge("publication" => publication))
      end

      def enqueue_verification(landing_page, commit_sha, deleted: false)
        Aicoo::CloudflarePagesDeploymentVerificationJob.set(wait: 30.seconds).perform_later(
          landing_page.id,
          commit_sha,
          deleted,
          1
        )
      end
    end
  end
end
