require "test_helper"

module Aicoo
  module Lovable
    class StaticArtifactValidatorTest < ActiveSupport::TestCase
      test "adds deterministic metadata GA4 and subpath-safe assets" do
        result = StaticArtifactValidator.new(
          files: {
            "index.html" => <<~HTML,
              <!doctype html>
              <html><head><title>AI受付</title><meta name="description" content="電話受付を自動化"></head>
              <body><a class="cta" href="#">相談する</a><script src="/assets/app.js"></script></body></html>
            HTML
            "assets/app.js" => "console.log('lp')"
          },
          page_path: "/ai-reception",
          public_url: "https://aicoo-lp.pages.dev/ai-reception/",
          service_url: "https://service.example.com",
          measurement_id: "G-ABC123"
        ).call

        html = result.files.fetch("index.html")
        assert_empty result.warnings
        assert_includes html, "width=device-width"
        assert_includes html, "https://aicoo-lp.pages.dev/ai-reception/"
        assert_includes html, "https://service.example.com"
        assert_includes html, "gtag/js?id=G-ABC123"
        assert_includes html, 'src="assets/app.js"'
      end

      test "rejects secrets and Lovable preview dependencies" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          StaticArtifactValidator.new(
            files: {
              "index.html" => '<title>LP</title><meta name="description" content="LP"><a href="https://service.example.com">CTA</a>',
              "app.js" => 'const preview = "https://draft.lovable.app";'
            },
            page_path: "/lp",
            public_url: "https://aicoo-lp.pages.dev/lp/",
            service_url: "https://service.example.com",
            measurement_id: "G-ABC123"
          ).call
        end

        assert_includes error.message, "Lovable Preview依存"
      end

      test "rejects a Measurement ID that differs from the Business shared GA4 setting" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          StaticArtifactValidator.new(
            files: {
              "index.html" => <<~HTML
                <html><head>
                  <title>LP</title>
                  <meta name="description" content="LP">
                  <script async src="https://www.googletagmanager.com/gtag/js?id=G-WRONG1"></script>
                </head><body><a class="cta" href="https://service.example.com">CTA</a></body></html>
              HTML
            },
            page_path: "/lp",
            public_url: "https://aicoo-lp.pages.dev/lp/",
            service_url: "https://service.example.com",
            measurement_id: "G-ABC123"
          ).call
        end

        assert_includes error.message, "G-WRONG1"
      end

      test "uses the Cloudflare public url when an initial publication has no service url" do
        result = StaticArtifactValidator.new(
          files: {
            "index.html" => <<~HTML
              <!doctype html>
              <html>
                <head><title>AI受付</title><meta name="description" content="電話受付を自動化"></head>
                <body>
                  <a href="#contact" data-cta="hero">問い合わせる</a>
                  <form id="contact"><button type="submit" data-cta="submit">送信</button></form>
                </body>
              </html>
            HTML
          },
          page_path: "/ai-reception",
          public_url: "https://aicoo-lp.pages.dev/ai-reception/",
          service_url: nil,
          measurement_id: "G-ABC123"
        ).call

        assert_includes result.warnings, "初回公開のため公開URLを自動登録します"
        assert_includes result.files.fetch("index.html"), "https://aicoo-lp.pages.dev/ai-reception/"
      end

      test "keeps the existing service url requirement for update publications" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          StaticArtifactValidator.new(
            files: {
              "index.html" => <<~HTML
                <!doctype html>
                <html>
                  <head><title>AI受付</title><meta name="description" content="電話受付を自動化"></head>
                  <body><a href="#contact" data-cta="hero">問い合わせる</a></body>
                </html>
              HTML
            },
            page_path: "/ai-reception",
            public_url: "https://aicoo-lp.pages.dev/ai-reception/",
            service_url: "https://service.example.com",
            measurement_id: "G-ABC123"
          ).call
        end

        assert_includes error.message, "Service本体URLへ遷移するCTAリンクがありません"
      end
    end
  end
end
