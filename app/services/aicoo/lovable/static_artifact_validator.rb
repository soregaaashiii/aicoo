require "nokogiri"
require "uri"

module Aicoo
  module Lovable
    class StaticArtifactValidator
      class InvalidArtifact < StandardError; end

      Result = Data.define(:files, :warnings)
      TEXT_EXTENSIONS = %w[.html .css .js .mjs .json .xml .txt .svg .webmanifest].freeze
      SECRET_PATTERNS = {
        "秘密鍵" => /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
        "GitHub Token" => /\b(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}\b/,
        "AWS Access Key" => /\bAKIA[0-9A-Z]{16}\b/,
        "Stripe Secret" => /\bsk_(?:live|test)_[A-Za-z0-9]{16,}\b/,
        "Supabase Service Role" => /\bSUPABASE_SERVICE_ROLE_KEY\b/
      }.freeze
      FORBIDDEN_RUNTIME_PATTERNS = {
        "localhost参照" => %r{https?://(?:localhost|127\.0\.0\.1)(?::\d+)?}i,
        "Lovable Preview依存" => %r{https?://[^/"']*lovable(?:project)?\.com|https?://[^/"']*lovable\.app}i,
        "Supabase backend依存" => %r{https?://[^/"']+\.supabase\.co|createClient\s*\(}i,
        "未解決の環境変数" => /\b(?:process\.env|import\.meta\.env)\b/
      }.freeze

      def initialize(files:, page_path:, public_url:, service_url:, measurement_id:)
        @files = files.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.b }
        @page_path = normalize_page_path(page_path)
        @public_url = valid_http_url(public_url, "Cloudflare公開URL")
        @service_url = valid_http_url(service_url, "Service URL")
        @measurement_id = measurement_id.to_s.strip
      end

      def call
        raise InvalidArtifact, "静的成果物にindex.htmlがありません。" unless files.key?("index.html")

        scan_for_secrets_and_runtime_dependencies!
        normalized = rewrite_subpath_assets(files)
        document = Nokogiri::HTML5(normalized.fetch("index.html"))
        ensure_head_metadata!(document)
        ensure_cta!(document)
        ensure_ga4!(document)
        normalized["index.html"] = document.to_html
        validate_asset_references!(normalized)
        Result.new(files: normalized, warnings: [])
      end

      private

      attr_reader :files, :page_path, :public_url, :service_url, :measurement_id

      def scan_for_secrets_and_runtime_dependencies!
        files.each do |path, content|
          next unless TEXT_EXTENSIONS.include?(File.extname(path).downcase)

          text = content.to_s
          SECRET_PATTERNS.each do |label, pattern|
            raise InvalidArtifact, "#{path}に#{label}が含まれています。" if text.match?(pattern)
          end
          FORBIDDEN_RUNTIME_PATTERNS.each do |label, pattern|
            raise InvalidArtifact, "#{path}に#{label}があります。" if text.match?(pattern)
          end
        end
      end

      def rewrite_subpath_assets(values)
        values.to_h do |path, content|
          next [ path, content ] unless TEXT_EXTENSIONS.include?(File.extname(path).downcase)

          text = content.to_s
            .gsub(%r{(["'(])/(assets/)}, '\1\2')
            .gsub(%r{(["'(])/(favicon(?:\.[a-z0-9]+)?)}, '\1\2')
          [ path, text ]
        end
      end

      def ensure_head_metadata!(document)
        html = document.at_css("html") || document.add_child("<html></html>").first
        head = document.at_css("head") || html.prepend_child("<head></head>").first
        head.add_child('<meta charset="utf-8">') unless head.at_css("meta[charset]")
        unless head.at_css('meta[name="viewport"]')
          head.add_child('<meta name="viewport" content="width=device-width, initial-scale=1">')
        end

        title = head.at_css("title")
        raise InvalidArtifact, "titleがありません。" if title&.text.to_s.strip.blank?
        description = head.at_css('meta[name="description"]')
        raise InvalidArtifact, "meta descriptionがありません。" if description&.[]("content").to_s.strip.blank?

        upsert_link(head, "canonical", public_url)
        upsert_meta(head, "property", "og:title", title.text.strip)
        upsert_meta(head, "property", "og:description", description["content"].to_s.strip)
        upsert_meta(head, "property", "og:url", public_url)
        upsert_meta(head, "property", "og:type", "website")
        upsert_meta(head, "name", "robots", "index,follow")
      end

      def ensure_cta!(document)
        cta = document.at_css("a[data-aicoo-cta], a.cta, a[class*='cta']")
        if cta && cta["href"].to_s.in?([ "", "#" ])
          cta["href"] = service_url
        end
        links = document.css("a[href]").map { |node| node["href"].to_s }
        return if links.any? { |href| same_destination?(href, service_url) }

        raise InvalidArtifact, "Service本体URLへ遷移するCTAリンクがありません。"
      end

      def ensure_ga4!(document)
        unless measurement_id.match?(/\AG-[A-Z0-9]+\z/i)
          raise InvalidArtifact, "Business共通GA4 Measurement IDが未設定です。"
        end

        html = document.to_html
        existing_ids = html.scan(%r{gtag/js\?id=(G-[A-Z0-9]+)}i).flatten +
          html.scan(/gtag\s*\(\s*['"]config['"]\s*,\s*['"](G-[A-Z0-9]+)['"]/i).flatten
        mismatched_ids = existing_ids.uniq.reject { |value| value.casecmp(measurement_id).zero? }
        if mismatched_ids.any?
          raise InvalidArtifact, "Business共通GA4と異なるMeasurement IDがあります: #{mismatched_ids.join(', ')}"
        end

        head = document.at_css("head")
        unless html.include?("gtag/js?id=#{measurement_id}")
          head.add_child(%(<script async src="https://www.googletagmanager.com/gtag/js?id=#{measurement_id}"></script>))
        end
        return if ga4_page_path_configured?(html)

        head.add_child(<<~HTML)
          <script>
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', '#{measurement_id}', { page_path: '#{page_path}' });
          </script>
        HTML
      end

      def ga4_page_path_configured?(html)
        escaped_path = Regexp.escape(page_path)
        html.match?(/gtag\s*\(\s*['"]config['"]\s*,\s*['"]#{Regexp.escape(measurement_id)}['"].*?page_path\s*:\s*['"]#{escaped_path}['"]/m)
      end

      def validate_asset_references!(values)
        document = Nokogiri::HTML5(values.fetch("index.html"))
        references = document.css("[src], link[href]").filter_map do |node|
          node["src"].presence || node["href"].presence
        end
        references.each do |reference|
          next if reference.start_with?("#", "data:", "mailto:", "tel:", "//") || reference.match?(%r{\Ahttps?://}i)

          path = reference.split(/[?#]/, 2).first.to_s.sub(%r{\A\./}, "").sub(%r{\A/+}, "")
          next if path.blank? || values.key?(path)

          raise InvalidArtifact, "index.htmlが存在しないasset #{reference} を参照しています。"
        end
      end

      def upsert_link(head, rel, href)
        node = head.at_css(%(link[rel="#{rel}"])) || head.add_child(%(<link rel="#{rel}">)).first
        node["href"] = href
      end

      def upsert_meta(head, attribute, key, content)
        node = head.at_css(%(meta[#{attribute}="#{key}"])) || head.add_child(%(<meta #{attribute}="#{key}">)).first
        node["content"] = content
      end

      def same_destination?(value, expected)
        value.to_s.delete_suffix("/") == expected.delete_suffix("/")
      end

      def valid_http_url(value, label)
        uri = URI.parse(value.to_s)
        return value.to_s if uri.is_a?(URI::HTTP) && uri.host.present?

        raise InvalidArtifact, "#{label}が未設定です。"
      rescue URI::InvalidURIError
        raise InvalidArtifact, "#{label}が不正です。"
      end

      def normalize_page_path(value)
        path = "/#{value.to_s.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}"
        path == "/" ? "/" : path
      end
    end
  end
end
