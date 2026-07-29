module Aicoo
  module LpIntegration
    class LandingPagePagePathAssigner
      Result = Data.define(:page_path, :generated, :source)
      GENERATED_PATH_PATTERN = %r{\A/[a-z0-9_-]+\z}.freeze

      def initialize(landing_page:)
        @landing_page = landing_page
      end

      def call
        BusinessPrototype.transaction do
          locked_rows = landing_page_rows.lock.order(:id).pluck(:id, :metadata)
          landing_page.reload
          existing = existing_page_path
          return Result.new(page_path: existing, generated: false, source: nil) if existing

          source, source_value = path_source
          base = sanitize_segment(source_value)
          base = "business-#{landing_page.business_id}" if base.blank?
          page_path = unique_page_path(base, locked_rows)
          raise ArgumentError, "自動生成したpage_pathが不正です。" unless page_path.match?(GENERATED_PATH_PATTERN)

          now = Time.current
          landing_page.update!(
            metadata: landing_page.metadata.to_h.merge(
              "ga4_page_path" => page_path,
              "page_path_generated_at" => now.iso8601,
              "page_path_generation_source" => source.to_s
            )
          )
          Result.new(page_path:, generated: true, source:)
        end
      end

      private

      attr_reader :landing_page

      def landing_page_rows
        BusinessPrototype.where(
          "metadata ->> 'role' IN (?)",
          BusinessPrototype::LANDING_PAGE_ROLES
        )
      end

      def existing_page_path
        value = landing_page.landing_page_ga4_path.to_s.strip
        value if value.present? && value != "/"
      end

      def path_source
        candidates = [
          [ :landing_page_slug, record_slug(landing_page) ],
          [ :business_slug, record_slug(landing_page.business) ],
          [ :repository_name, repository_name ],
          [ :business_id, "business-#{landing_page.business_id}" ]
        ]
        candidates.find { |(_, value)| sanitize_segment(value).present? }
      end

      def record_slug(record)
        return record.slug if record.respond_to?(:slug) && record.slug.present?

        metadata = record.respond_to?(:metadata) ? record.metadata.to_h : {}
        metadata["slug"].presence || metadata["lp_slug"].presence
      end

      def repository_name
        repository = Aicoo::Lovable::GithubRepositoryIdentity.normalize(
          landing_page.landing_page_repository_url
        )
        repository.to_s.split("/").last.presence ||
          landing_page.metadata.to_h["repository_name"].presence ||
          landing_page.business.repository_name.presence
      end

      def sanitize_segment(value)
        value.to_s.downcase.strip
          .gsub(/[^a-z0-9_-]+/, "-")
          .gsub(/\A[-_]+|[-_]+\z/, "")
          .presence
      end

      def unique_page_path(base, locked_rows)
        used_paths = locked_rows.each_with_object({}) do |(id, metadata), paths|
          next if id == landing_page.id

          page_path = canonical_page_path(metadata.to_h["ga4_page_path"])
          github_path = page_path_from_github_path(metadata.to_h["github_path"])
          paths[page_path] = true if page_path
          paths[github_path] = true if github_path
        end
        candidate = "/#{base}"
        suffix = 2
        while used_paths[candidate]
          candidate = "/#{base}-#{suffix}"
          suffix += 1
        end
        candidate
      end

      def canonical_page_path(value)
        path = value.to_s.strip
        return if path.blank? || path == "/"

        "/#{path.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}"
      end

      def page_path_from_github_path(value)
        path = value.to_s.tr("\\", "/").sub(%r{\A/+}, "")
        return unless path.start_with?("public/")

        canonical_page_path(path.delete_prefix("public/"))
      end
    end
  end
end
