require "base64"
require "json"
require "nokogiri"
require "pathname"
require "uri"

module Aicoo
  class PrototypeInspector
    MAX_TEXT_LENGTH = 20_000

    def initialize(prototype, fetcher: Aicoo::PublicHttpFetcher.new)
      @prototype = prototype
      @fetcher = fetcher
    end

    def call
      case prototype.prototype_type
      when "github" then inspect_github
      when "url", "lovable", "figma", "render" then inspect_web_page
      when "local" then inspect_local
      else inspect_reference
      end
    rescue Aicoo::PublicHttpFetcher::Error, JSON::ParserError, Errno::ENOENT, Errno::EACCES => e
      {
        "source" => prototype.prototype_type,
        "location" => prototype.location,
        "inspection_status" => "limited",
        "inspection_warning" => e.message
      }
    end

    private

    attr_reader :prototype, :fetcher

    def inspect_github
      owner, repository = github_repository_parts
      repository_response = fetcher.get(
        "https://api.github.com/repos/#{owner}/#{repository}",
        headers: github_headers
      )
      contents_response = fetcher.get(
        "https://api.github.com/repos/#{owner}/#{repository}/contents",
        headers: github_headers
      )
      repository_payload = JSON.parse(repository_response.body)
      root_entries = JSON.parse(contents_response.body)
      readme = fetch_github_readme(owner, repository)
      file_names = Array(root_entries).filter_map { |entry| entry["name"] }

      {
        "source" => "github",
        "location" => prototype.location,
        "inspection_status" => "succeeded",
        "repository" => repository_payload.slice("full_name", "description", "homepage", "language", "topics", "default_branch"),
        "readme" => readme.to_s.first(MAX_TEXT_LENGTH),
        "root_entries" => file_names.first(100),
        "technology_signals" => technology_signals(file_names.join(" ") + " " + readme.to_s)
      }
    end

    def fetch_github_readme(owner, repository)
      response = fetcher.get(
        "https://api.github.com/repos/#{owner}/#{repository}/readme",
        headers: github_headers
      )
      payload = JSON.parse(response.body)
      Base64.decode64(payload["content"].to_s)
    rescue Aicoo::PublicHttpFetcher::Error
      nil
    end

    def github_repository_parts
      uri = URI.parse(prototype.location)
      unless uri.host.to_s.downcase.in?(%w[github.com www.github.com])
        raise Aicoo::PublicHttpFetcher::Error, "GitHub repository URL is required"
      end

      parts = uri.path.to_s.split("/").compact_blank
      unless parts.size >= 2 && parts.first(2).all? { |part| part.match?(/\A[\w.-]+\z/) }
        raise Aicoo::PublicHttpFetcher::Error, "GitHub repository URL is invalid"
      end

      [ parts[0], parts[1].delete_suffix(".git") ]
    rescue URI::InvalidURIError
      raise Aicoo::PublicHttpFetcher::Error, "GitHub repository URL is invalid"
    end

    def github_headers
      {
        "Accept" => "application/vnd.github+json",
        "Authorization" => ENV["GITHUB_TOKEN"].present? ? "Bearer #{ENV.fetch("GITHUB_TOKEN")}" : nil
      }
    end

    def inspect_web_page
      response = fetcher.get(prototype.location, headers: { "Accept" => "text/html,application/xhtml+xml" })
      document = Nokogiri::HTML(response.body)
      title = document.at_css("title")&.text.to_s.squish
      description = document.at_css('meta[name="description"]')&.[]("content").to_s.squish
      headings = document.css("h1, h2").first(20).map { |node| node.text.squish }.compact_blank
      body_text = document.at_css("body")&.text.to_s.squish.first(MAX_TEXT_LENGTH)

      {
        "source" => prototype.prototype_type,
        "location" => prototype.location,
        "resolved_url" => response.url,
        "inspection_status" => "succeeded",
        "title" => title,
        "meta_description" => description,
        "headings" => headings,
        "body_excerpt" => body_text,
        "technology_signals" => technology_signals(response.body)
      }
    end

    def inspect_local
      path = Pathname.new(prototype.location).expand_path
      raise Aicoo::PublicHttpFetcher::Error, "local path does not exist" unless path.directory?

      path = path.realpath
      allowed_root = local_roots.find { |root| path.to_s == root.to_s || path.to_s.start_with?("#{root}/") }
      raise Aicoo::PublicHttpFetcher::Error, "local path is outside configured roots" unless allowed_root

      root_entries = path.children.first(100).map { |entry| entry.basename.to_s }
      files = %w[README.md README package.json Gemfile Dockerfile docker-compose.yml].index_with do |file_name|
        file = path.join(file_name)
        file.file? ? file.read(MAX_TEXT_LENGTH) : nil
      rescue ArgumentError
        file.read.to_s.first(MAX_TEXT_LENGTH)
      end.compact

      {
        "source" => "local",
        "location" => path.to_s,
        "inspection_status" => "succeeded",
        "root_entries" => root_entries,
        "files" => files,
        "technology_signals" => technology_signals(root_entries.join(" ") + " " + files.values.join(" "))
      }
    end

    def local_roots
      configured = ENV.fetch("BUSINESS_PROTOTYPE_LOCAL_ROOTS", "").split(File::PATH_SEPARATOR).compact_blank
      configured << Rails.root.to_s unless Rails.env.production?
      configured.filter_map do |root|
        path = Pathname.new(root).expand_path
        path.realpath if path.directory?
      end.uniq
    end

    def inspect_reference
      {
        "source" => prototype.prototype_type,
        "location" => prototype.location,
        "inspection_status" => "registered"
      }
    end

    def technology_signals(text)
      corpus = text.to_s.downcase
      {
        "rails" => corpus.include?("gemfile") || corpus.include?("ruby on rails"),
        "react" => corpus.include?("react"),
        "next_js" => corpus.include?("next.js") || corpus.include?("nextjs"),
        "vite" => corpus.include?("vite"),
        "docker" => corpus.include?("dockerfile") || corpus.include?("docker-compose"),
        "wordpress" => corpus.include?("wp-content") || corpus.include?("wordpress"),
        "shopify" => corpus.include?("shopify")
      }.select { |_key, present| present }.keys
    end
  end
end
