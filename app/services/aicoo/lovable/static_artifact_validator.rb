require "nokogiri"
require "set"
require "uri"

module Aicoo
  module Lovable
    class StaticArtifactValidator
      class InvalidArtifact < StandardError
        attr_reader :details

        def initialize(message, details: {})
          @details = details
          super(message)
        end
      end

      Result = Data.define(:files, :warnings)
      TEXT_EXTENSIONS = %w[
        .html .htm .css .js .mjs .cjs .jsx .ts .tsx .json .xml .txt .svg .webmanifest
      ].freeze
      JAVASCRIPT_EXTENSIONS = %w[.js .mjs .cjs .jsx .ts .tsx].freeze
      HTML_EXTENSIONS = %w[.html .htm].freeze
      LOCAL_RUNTIME_URL_PATTERN =
        %r{\A(?:https?:|wss?:)?//(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?(?:[/?#]|\z)}i
      SECRET_PATTERNS = {
        "秘密鍵" => /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
        "GitHub Token" => /\b(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}\b/,
        "AWS Access Key" => /\bAKIA[0-9A-Z]{16}\b/,
        "Stripe Secret" => /\bsk_(?:live|test)_[A-Za-z0-9]{16,}\b/,
        "Supabase Service Role" => /\bSUPABASE_SERVICE_ROLE_KEY\b/
      }.freeze
      FORBIDDEN_RUNTIME_PATTERNS = {
        "Lovable Preview依存" => %r{https?://[^/"']*lovable(?:project)?\.com|https?://[^/"']*lovable\.app}i,
        "Supabase backend依存" => %r{https?://[^/"']+\.supabase\.co|createClient\s*\(}i,
        "未解決の環境変数" =>
          /\bprocess\.env\b|import\.meta\.env(?!\.(?:DEV|PROD|SSR|MODE|BASE_URL)\b)/
      }.freeze

      def initialize(files:, page_path:, public_url:, service_url:, measurement_id:)
        @files = files.to_h.transform_keys(&:to_s).transform_values { |value| value.to_s.b }
        @page_path = normalize_page_path(page_path)
        @public_url = valid_http_url(public_url, "Cloudflare公開URL")
        @service_url_fallback = service_url.blank? || same_destination?(service_url, @public_url)
        @service_url = valid_http_url(service_url.presence || @public_url, "Service URL")
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
        Result.new(
          files: normalized,
          warnings: service_url_fallback ? [ "初回公開のため公開URLを自動登録します" ] : []
        )
      end

      private

      attr_reader :files, :page_path, :public_url, :service_url, :measurement_id, :service_url_fallback

      def scan_for_secrets_and_runtime_dependencies!
        files.each do |path, content|
          next unless TEXT_EXTENSIONS.include?(File.extname(path).downcase)

          text = content.to_s.dup.force_encoding(Encoding::UTF_8).scrub
          SECRET_PATTERNS.each do |label, pattern|
            raise InvalidArtifact, "#{path}に#{label}が含まれています。" if text.match?(pattern)
          end
          FORBIDDEN_RUNTIME_PATTERNS.each do |label, pattern|
            raise InvalidArtifact, "#{path}に#{label}があります。" if text.match?(pattern)
          end
          validate_runtime_urls!(path, text)
        end
      end

      def validate_runtime_urls!(path, text)
        extension = File.extname(path).downcase
        finding = if JAVASCRIPT_EXTENSIONS.include?(extension)
          JavaScriptRuntimeUrlScanner.new(text).call
        elsif HTML_EXTENSIONS.include?(extension)
          html_runtime_url_finding(text)
        elsif extension == ".css"
          css_runtime_url_finding(text)
        end
        return unless finding

        details = finding.merge("file" => path)
        raise InvalidArtifact.new(
          "localhostへの実通信が検出されました。",
          details:
        )
      end

      def html_runtime_url_finding(text)
        document = Nokogiri::HTML5(text)
        document.css("iframe[src], script[src], img[src], link[href]").each do |node|
          attribute = node.name == "link" ? "href" : "src"
          url = node[attribute].to_s
          next unless local_runtime_url?(url)

          return {
            "line" => node.line,
            "url" => url,
            "api" => "#{node.name} #{attribute}"
          }
        end
        document.css("script:not([src])").each do |node|
          finding = JavaScriptRuntimeUrlScanner.new(node.text.to_s, line_offset: node.line - 1).call
          return finding if finding
        end
        nil
      end

      def css_runtime_url_finding(text)
        without_comments = text.gsub(%r{/\*.*?\*/}m) { |comment| "\n" * comment.count("\n") }
        match = without_comments.match(
          /url\(\s*(?:["'])?((?:https?:|wss?:)?\/\/(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?[^"')\s]*)(?:["'])?\s*\)/i
        )
        return unless match

        {
          "line" => without_comments[0...match.begin(1)].count("\n") + 1,
          "url" => match[1],
          "api" => "CSS url"
        }
      end

      def local_runtime_url?(value)
        value.to_s.match?(LOCAL_RUNTIME_URL_PATTERN)
      end

      class JavaScriptRuntimeUrlScanner
        Token = Data.define(:type, :value, :line)
        HTTP_METHODS = %w[get post put patch delete head options request].freeze
        DOM_URL_ATTRIBUTES = %w[src href].freeze

        def initialize(source, line_offset: 0)
          @source = source
          @line_offset = line_offset
        end

        def call
          collect_bindings
          tokens.each_with_index do |token, index|
            finding = network_call_finding(token, index) ||
              xhr_open_finding(token, index) ||
              dom_url_finding(token, index)
            return finding if finding
          end
          nil
        end

        private

        attr_reader :source, :line_offset

        def network_call_finding(token, index)
          return call_finding(index + 1, 0, "fetch") if identifier?(token, "fetch") && punct?(index + 1, "(")
          if identifier?(token, "axios")
            return call_finding(index + 1, 0, "axios") if punct?(index + 1, "(")
            if punct?(index + 1, ".") && HTTP_METHODS.include?(tokens[index + 2]&.value) && punct?(index + 3, "(")
              return call_finding(index + 3, 0, "axios.#{tokens[index + 2].value}")
            end
          end
          if %w[WebSocket EventSource].include?(token.value) && punct?(index + 1, "(")
            return call_finding(index + 1, 0, token.value)
          end
          nil
        end

        def xhr_open_finding(token, index)
          return unless token.type == :identifier && xhr_variables.include?(token.value)
          return unless punct?(index + 1, ".") && identifier?(tokens[index + 2], "open") && punct?(index + 3, "(")

          call_finding(index + 3, 1, "XMLHttpRequest.open")
        end

        def dom_url_finding(token, index)
          if token.type == :identifier &&
              punct?(index + 1, ".") &&
              DOM_URL_ATTRIBUTES.include?(tokens[index + 2]&.value) &&
              punct?(index + 3, "=")
            return value_finding(tokens[index + 4], "DOM #{tokens[index + 2].value}")
          end
          return unless identifier?(token, "setAttribute") && punct?(index + 1, "(")

          attribute = argument_token(index + 1, 0)
          return unless attribute&.type == :string && DOM_URL_ATTRIBUTES.include?(attribute.value.downcase)

          value_finding(argument_token(index + 1, 1), "setAttribute #{attribute.value.downcase}")
        end

        def call_finding(open_index, argument_index, api)
          value_finding(argument_token(open_index, argument_index), api)
        end

        def value_finding(token, api)
          return unless token

          value_token = token.type == :identifier ? literal_bindings[token.value] : token
          return unless value_token&.type == :string
          return unless value_token.value.match?(StaticArtifactValidator::LOCAL_RUNTIME_URL_PATTERN)

          {
            "line" => value_token.line,
            "url" => value_token.value,
            "api" => api
          }
        end

        def argument_token(open_index, target_argument)
          depth = 0
          argument = 0
          index = open_index + 1
          while (token = tokens[index])
            if token.type == :punctuation
              case token.value
              when "(", "[", "{"
                depth += 1
              when ")", "]", "}"
                return if depth.zero?

                depth -= 1
              when ","
                argument += 1 if depth.zero?
                index += 1
                next
              end
            end
            if depth.zero? && argument == target_argument && token.type.in?([ :string, :identifier ])
              return token
            end
            index += 1
          end
          nil
        end

        def collect_bindings
          tokens.each_with_index do |token, index|
            next unless token.type == :identifier

            if %w[const let var].include?(token.value) &&
                tokens[index + 1]&.type == :identifier &&
                punct?(index + 2, "=")
              assigned = tokens[index + 3]
              literal_bindings[tokens[index + 1].value] = assigned if assigned&.type == :string
              if identifier?(assigned, "new") && identifier?(tokens[index + 4], "XMLHttpRequest")
                xhr_variables << tokens[index + 1].value
              end
            end
          end
        end

        def literal_bindings
          @literal_bindings ||= {}
        end

        def xhr_variables
          @xhr_variables ||= Set.new
        end

        def tokens
          @tokens ||= tokenize
        end

        def tokenize
          values = []
          index = 0
          line = 1 + line_offset
          while index < source.length
            character = source[index]
            if character.match?(/\s/)
              line += 1 if character == "\n"
              index += 1
            elsif character == "/" && source[index + 1] == "/"
              index += 2
              index += 1 while index < source.length && source[index] != "\n"
            elsif character == "/" && source[index + 1] == "*"
              index += 2
              until index >= source.length || (source[index] == "*" && source[index + 1] == "/")
                line += 1 if source[index] == "\n"
                index += 1
              end
              index += 2
            elsif character.in?([ "'", '"' ])
              token, index, line = read_string(index, line, character)
              values << token
            elsif character == "`"
              token, index, line = read_template(index, line)
              values << token if token
            elsif character.match?(/[A-Za-z_$]/)
              start = index
              index += 1
              index += 1 while index < source.length && source[index].match?(/[A-Za-z0-9_$]/)
              values << Token.new(type: :identifier, value: source[start...index], line:)
            else
              values << Token.new(type: :punctuation, value: character, line:)
              index += 1
            end
          end
          values
        end

        def read_string(index, line, quote)
          start_line = line
          value = +""
          index += 1
          while index < source.length
            character = source[index]
            if character == quote
              return [ Token.new(type: :string, value:, line: start_line), index + 1, line ]
            end
            if character == "\\"
              decoded, index = decode_escape(index)
              value << decoded
              next
            end
            line += 1 if character == "\n"
            value << character
            index += 1
          end
          [ Token.new(type: :string, value:, line: start_line), index, line ]
        end

        def read_template(index, line)
          start_line = line
          value = +""
          dynamic = false
          index += 1
          while index < source.length
            character = source[index]
            if character == "`"
              token = dynamic ? nil : Token.new(type: :string, value:, line: start_line)
              return [ token, index + 1, line ]
            end
            if character == "$" && source[index + 1] == "{"
              dynamic = true
            end
            if character == "\\"
              decoded, index = decode_escape(index)
              value << decoded
              next
            end
            line += 1 if character == "\n"
            value << character
            index += 1
          end
          [ nil, index, line ]
        end

        def decode_escape(index)
          marker = source[index + 1]
          case marker
          when "x"
            digits = source[(index + 2), 2]
            [ digits.match?(/\A[0-9a-f]{2}\z/i) ? digits.to_i(16).chr : "x#{digits}", index + 4 ]
          when "u"
            digits = source[(index + 2), 4]
            [ digits.match?(/\A[0-9a-f]{4}\z/i) ? [ digits.to_i(16) ].pack("U") : "u#{digits}", index + 6 ]
          else
            [ marker.to_s, index + 2 ]
          end
        end

        def identifier?(token, value)
          token&.type == :identifier && token.value == value
        end

        def punct?(index, value)
          token = tokens[index]
          token&.type == :punctuation && token.value == value
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
        return if service_url_fallback && local_conversion_target?(document)

        raise InvalidArtifact, "Service本体URLへ遷移するCTAリンクがありません。"
      end

      def local_conversion_target?(document)
        document.at_css(
          "a[data-aicoo-cta], a[data-cta], button[data-aicoo-cta], button[data-cta], form"
        ).present?
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
