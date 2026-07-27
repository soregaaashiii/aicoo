require "base64"
require "cgi"
require "json"

module Aicoo
  module CloudflarePages
    class LandingPageAssetBundle
      Result = Data.define(:files, :source)

      def initialize(landing_page:, generation_run: nil)
        @landing_page = landing_page
        @generation_run = generation_run
      end

      def call
        supplied = supplied_files
        return Result.new(files: supplied, source: "lovable_output") if supplied.any?

        Result.new(files: generated_files, source: "aicoo_landing_page")
      end

      private

      attr_reader :landing_page, :generation_run

      def supplied_files
        payload = generation_run&.metadata.to_h&.deep_stringify_keys || {}
        raw = payload["publication_files"] ||
          payload.dig("lovable_response", "files") ||
          parsed_response(payload)["files"]
        normalize_files(raw)
      end

      def parsed_response(payload)
        JSON.parse(generation_run&.response.to_s.presence || "{}")
      rescue JSON::ParserError
        payload["lovable_response"].to_h
      end

      def normalize_files(raw)
        pairs = case raw
        when Hash
          raw.filter_map do |path, value|
            values = value.is_a?(Hash) ? value.deep_stringify_keys : { "content" => value }
            [ path, decode_content(values) ] if values.key?("content")
          end
        when Array
          raw.filter_map do |item|
            values = item.to_h.deep_stringify_keys
            [ values["path"], decode_content(values) ] if values["path"].present? && values.key?("content")
          end
        else
          []
        end
        pairs.to_h do |path, content|
          [ normalize_relative_path(path), content.to_s.b ]
        end
      end

      def decode_content(values)
        return Base64.decode64(values["content"].to_s) if values["encoding"] == "base64"

        values["content"]
      end

      def normalize_relative_path(path)
        value = path.to_s.tr("\\", "/").sub(%r{\A(?:public|dist)/}, "").sub(%r{\A/+}, "")
        parts = value.split("/").reject { |part| part.blank? || part == "." }
        raise ArgumentError, "LPファイルのpathが不正です。" if parts.empty? || parts.include?("..")

        parts.join("/")
      end

      def generated_files
        {
          "index.html" => generated_html,
          "styles.css" => generated_css,
          "app.js" => generated_javascript
        }
      end

      def generated_html
        internal = internal_landing_page
        title = internal&.effective_seo_title.presence || landing_page.landing_page_name
        description = internal&.effective_seo_description.presence || landing_page.metadata.to_h["improvement_target"].presence || title
        headline = internal&.public_headline.presence || title
        subheadline = internal&.public_subheadline.presence || description
        body = internal&.body.to_s
        cta = internal&.cta_text.presence || landing_page.metadata.to_h["cta"].presence || "お問い合わせ"
        <<~HTML
          <!doctype html>
          <html lang="ja">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{escape(title)}</title>
              <meta name="description" content="#{escape(description)}">
              <link rel="stylesheet" href="styles.css">
            </head>
            <body>
              <main>
                <section class="hero">
                  <p class="brand">#{escape(landing_page.business.name)}</p>
                  <h1>#{escape(headline)}</h1>
                  <p class="lead">#{escape(subheadline)}</p>
                  <a class="cta" href="#contact" data-aicoo-cta>#{escape(cta)}</a>
                </section>
                <section class="content">
                  #{body_blocks(body)}
                </section>
                <section class="contact" id="contact">
                  <h2>#{escape(cta)}</h2>
                  <p>詳しい内容について、お気軽にお問い合わせください。</p>
                </section>
              </main>
              <script src="app.js" defer></script>
            </body>
          </html>
        HTML
      end

      def generated_css
        <<~CSS
          :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #17211d; background: #f5f7f6; }
          * { box-sizing: border-box; }
          body { margin: 0; }
          main { width: min(100%, 1120px); margin: 0 auto; background: #fff; }
          .hero { min-height: 72vh; padding: clamp(48px, 9vw, 112px) clamp(24px, 7vw, 84px); display: grid; align-content: center; background: #173b32; color: #fff; }
          .brand { margin: 0 0 24px; font-weight: 700; }
          h1 { margin: 0; max-width: 900px; font-size: clamp(2.25rem, 7vw, 5rem); line-height: 1.08; letter-spacing: 0; }
          .lead { max-width: 680px; margin: 24px 0 32px; font-size: 1.15rem; line-height: 1.8; }
          .cta { justify-self: start; padding: 14px 22px; background: #f3cf52; color: #17211d; font-weight: 700; text-decoration: none; border-radius: 6px; }
          .content, .contact { padding: clamp(40px, 7vw, 80px) clamp(24px, 7vw, 84px); }
          .content p, .contact p { max-width: 760px; line-height: 1.9; }
          .contact { background: #e9f0ed; }
          @media (max-width: 640px) { .hero { min-height: 78vh; } h1 { font-size: 2.5rem; } }
        CSS
      end

      def generated_javascript
        <<~JAVASCRIPT
          document.querySelectorAll("[data-aicoo-cta]").forEach((element) => {
            element.addEventListener("click", () => {
              window.dataLayer = window.dataLayer || [];
              window.dataLayer.push({ event: "generate_lead", page_path: window.location.pathname });
            });
          });
        JAVASCRIPT
      end

      def body_blocks(value)
        blocks = value.lines.map(&:strip).reject(&:blank?)
        blocks = [ landing_page.metadata.to_h["improvement_target"].presence || landing_page.landing_page_name ] if blocks.empty?
        blocks.map { |block| "<p>#{escape(block)}</p>" }.join("\n")
      end

      def internal_landing_page
        id = landing_page.metadata.to_h["lovable_landing_page_id"]
        landing_page.business.aicoo_lab_landing_pages.find_by(id:) if id.present?
      end

      def escape(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
