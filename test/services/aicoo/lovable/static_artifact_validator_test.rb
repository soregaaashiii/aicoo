require "test_helper"
require "fileutils"
require "tmpdir"

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

      test "warns and continues when the Business shared GA4 Measurement ID is missing" do
        result = StaticArtifactValidator.new(
          files: {
            "index.html" => <<~HTML
              <!doctype html>
              <html>
                <head><title>LP</title><meta name="description" content="LP"></head>
                <body><a class="cta" href="https://service.example.com">CTA</a></body>
              </html>
            HTML
          },
          page_path: "/lp",
          public_url: "https://aicoo-lp.pages.dev/lp/",
          service_url: "https://service.example.com",
          measurement_id: nil
        ).call

        assert_includes result.warnings, StaticArtifactValidator::GA4_MISSING_WARNING
        assert_not_includes result.files.fetch("index.html"), "googletagmanager.com/gtag"
      end

      test "rejects a configured but invalid GA4 Measurement ID" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          StaticArtifactValidator.new(
            files: {
              "index.html" => <<~HTML
                <!doctype html>
                <html>
                  <head><title>LP</title><meta name="description" content="LP"></head>
                  <body><a class="cta" href="https://service.example.com">CTA</a></body>
                </html>
              HTML
            },
            page_path: "/lp",
            public_url: "https://aicoo-lp.pages.dev/lp/",
            service_url: "https://service.example.com",
            measurement_id: "UA-INVALID"
          ).call
        end

        assert_equal "Business共通GA4 Measurement IDが不正です。", error.message
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

      test "allows localhost in comments error messages dev checks unused strings and source maps" do
        result = validate_javascript(<<~JAVASCRIPT)
          // Documentation: http://localhost:3000
          const message = "Could not connect to http://localhost:3000";
          if (import.meta.env.DEV) console.debug(message);
          const unused = "http://127.0.0.1:4000/debug";
          const origin = window.origin !== "null" ? window.origin : "http://localhost";
          //# sourceMappingURL=http://localhost:3000/app.js.map
        JAVASCRIPT

        assert result.files.key?("assets/app.js")
      end

      test "rejects a localhost fetch with file line url and api details" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_javascript(<<~JAVASCRIPT)
            const label = "request";
            fetch("http://localhost:3000/api");
          JAVASCRIPT
        end

        assert_equal "localhostへの実通信が検出されました。", error.message
        assert_equal "assets/app.js", error.details.fetch("file")
        assert_equal 2, error.details.fetch("line")
        assert_equal "http://localhost:3000/api", error.details.fetch("url")
        assert_equal "fetch", error.details.fetch("api")
      end

      test "rejects a loopback axios request" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_javascript('axios("http://127.0.0.1/api");')
        end

        assert_equal "axios", error.details.fetch("api")
        assert_equal "http://127.0.0.1/api", error.details.fetch("url")
      end

      test "rejects a localhost WebSocket connection" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_javascript('new WebSocket("ws://localhost:5173/socket");')
        end

        assert_equal "WebSocket", error.details.fetch("api")
        assert_equal "ws://localhost:5173/socket", error.details.fetch("url")
      end

      test "rejects a localhost iframe source" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          StaticArtifactValidator.new(
            files: {
              "index.html" => <<~HTML
                <!doctype html>
                <html>
                  <head><title>LP</title><meta name="description" content="LP"></head>
                  <body>
                    <a class="cta" href="https://service.example.com">CTA</a>
                    <iframe src="http://localhost:3000/preview"></iframe>
                  </body>
                </html>
              HTML
            },
            page_path: "/lp",
            public_url: "https://aicoo-lp.pages.dev/lp/",
            service_url: "https://service.example.com",
            measurement_id: "G-ABC123"
          ).call
        end

        assert_equal "iframe src", error.details.fetch("api")
        assert_equal "http://localhost:3000/preview", error.details.fetch("url")
      end

      test "matches a page path prefixed script to the artifact relative path" do
        result = validate_assets(
          body: '<script src="/voice-analysis-pro/assets/app.js"></script>',
          assets: { "assets/app.js" => "console.log('app')" }
        )

        assert result.files.key?("assets/app.js")
      end

      test "removes query and fragment before matching an asset" do
        result = validate_assets(
          head: '<link rel="stylesheet" href="/voice-analysis-pro/assets/app.css?v=1#top">',
          assets: { "assets/app.css" => "body { color: black; }" }
        )

        assert result.files.key?("assets/app.css")
      end

      test "matches a relative asset path" do
        result = validate_assets(
          body: '<script src="assets/app.js"></script>',
          assets: { "assets/app.js" => "console.log('app')" }
        )

        assert result.files.key?("assets/app.js")
      end

      test "keeps existing root asset matching" do
        result = validate_assets(
          body: '<script src="/assets/app.js"></script>',
          assets: { "assets/app.js" => "console.log('app')" }
        )

        assert result.files.key?("assets/app.js")
      end

      test "does not remove a page path without an exact path boundary" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_assets(
            body: '<script src="/voice-analysis-production/assets/app.js"></script>',
            assets: { "assets/app.js" => "console.log('app')" }
          )
        end

        assert_equal "/voice-analysis-production/assets/app.js", error.details.fetch("url")
        assert_equal "voice-analysis-production/assets/app.js", error.details.fetch("normalized_path")
      end

      test "does not check external https assets locally" do
        result = validate_assets(
          body: '<script src="https://cdn.example.com/app.js"></script>'
        )

        assert result.files.key?("index.html")
      end

      test "does not check data urls locally" do
        result = validate_assets(
          body: '<img src="data:image/png;base64,AAAA" alt="">'
        )

        assert result.files.key?("index.html")
      end

      test "checks every srcset candidate" do
        result = validate_assets(
          body: <<~HTML,
            <picture>
              <source srcset="/voice-analysis-pro/assets/large.webp 2x, assets/small.webp?v=1 1x">
              <img src="assets/small.webp" alt="">
            </picture>
          HTML
          assets: {
            "assets/large.webp" => "large",
            "assets/small.webp" => "small"
          }
        )

        assert result.files.key?("assets/large.webp")
        assert result.files.key?("assets/small.webp")
      end

      test "matches a page path prefixed CSS url" do
        result = validate_assets(
          head: '<link rel="stylesheet" href="assets/app.css">',
          assets: {
            "assets/app.css" => 'body { background: url("/voice-analysis-pro/assets/bg.png"); }',
            "assets/bg.png" => "image"
          }
        )

        assert result.files.key?("assets/bg.png")
      end

      test "matches a page path prefixed CSS import" do
        result = validate_assets(
          head: '<link rel="stylesheet" href="assets/app.css">',
          assets: {
            "assets/app.css" => '@import "/voice-analysis-pro/assets/theme.css";',
            "assets/theme.css" => "body { color: black; }"
          }
        )

        assert result.files.key?("assets/theme.css")
      end

      test "rejects plain path traversal" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_assets(body: '<script src="../secret.js"></script>')
        end

        assert_includes error.message, "成果物外"
        assert_equal "../secret.js", error.details.fetch("url")
      end

      test "rejects URL encoded path traversal" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_assets(body: '<script src="%2e%2e/secret.js"></script>')
        end

        assert_includes error.message, "成果物外"
        assert_equal "../secret.js", error.details.fetch("normalized_path")
      end

      test "rejects a symlink that resolves outside the artifact root" do
        Dir.mktmpdir("artifact-root") do |root|
          Dir.mktmpdir("outside-root") do |outside|
            FileUtils.mkdir_p(File.join(root, "assets"))
            File.write(File.join(outside, "app.js"), "outside")
            File.symlink(File.join(outside, "app.js"), File.join(root, "assets", "app.js"))

            error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
              validate_assets(
                body: '<script src="assets/app.js"></script>',
                assets: { "assets/app.js" => "outside" },
                artifact_root: root
              )
            end

            assert_includes error.message, "成果物外"
          end
        end
      end

      test "uses base href without removing the page path twice" do
        result = validate_assets(
          head: '<base href="/voice-analysis-pro/">',
          body: '<script src="assets/app.js"></script>',
          assets: { "assets/app.js" => "console.log('app')" }
        )

        assert result.files.key?("assets/app.js")
      end

      test "records original and normalized paths when an asset is missing" do
        error = assert_raises(StaticArtifactValidator::InvalidArtifact) do
          validate_assets(
            head: '<link rel="stylesheet" href="/voice-analysis-pro/assets/missing.css?v=1">',
            artifact_root_label: "dist/client/"
          )
        end

        assert_equal "公開用ファイルから参照されているassetが見つかりません。", error.message
        assert_equal "/voice-analysis-pro/assets/missing.css?v=1", error.details.fetch("url")
        assert_equal "assets/missing.css", error.details.fetch("normalized_path")
        assert_equal "/voice-analysis-pro", error.details.fetch("page_path")
        assert_equal "index.html", error.details.fetch("file")
        assert_equal "link href", error.details.fetch("api")
        assert_equal "dist/client/", error.details.fetch("artifact_root")
      end

      test "checks all supported HTML asset attributes" do
        result = validate_assets(
          head: <<~HTML,
            <link rel="manifest" href="/voice-analysis-pro/site.webmanifest">
          HTML
          body: <<~HTML,
            <img src="assets/image.png" alt="">
            <source src="assets/movie.webm">
            <video src="assets/movie.mp4" poster="assets/poster.jpg"></video>
            <audio src="assets/sound.mp3"></audio>
            <iframe src="assets/frame.html"></iframe>
          HTML
          assets: {
            "site.webmanifest" => "{}",
            "assets/image.png" => "image",
            "assets/movie.webm" => "webm",
            "assets/movie.mp4" => "mp4",
            "assets/poster.jpg" => "poster",
            "assets/sound.mp3" => "mp3",
            "assets/frame.html" => "<html></html>"
          }
        )

        assert_equal 8, result.files.size
      end

      private

      def validate_assets(
        head: "",
        body: "",
        assets: {},
        page_path: "/voice-analysis-pro",
        artifact_root: nil,
        artifact_root_label: nil
      )
        StaticArtifactValidator.new(
          files: {
            "index.html" => <<~HTML,
              <!doctype html>
              <html>
                <head>
                  <title>Voice Analysis</title>
                  <meta name="description" content="Voice Analysis LP">
                  #{head}
                </head>
                <body>
                  <a class="cta" href="https://service.example.com">CTA</a>
                  #{body}
                </body>
              </html>
            HTML
            **assets
          },
          page_path:,
          public_url: "https://aicoo-lp.pages.dev#{page_path}/",
          service_url: "https://service.example.com",
          measurement_id: nil,
          artifact_root:,
          artifact_root_label:
        ).call
      end

      def validate_javascript(source)
        StaticArtifactValidator.new(
          files: {
            "index.html" => <<~HTML,
              <!doctype html>
              <html>
                <head><title>LP</title><meta name="description" content="LP"></head>
                <body><a class="cta" href="https://service.example.com">CTA</a></body>
              </html>
            HTML
            "assets/app.js" => source
          },
          page_path: "/lp",
          public_url: "https://aicoo-lp.pages.dev/lp/",
          service_url: "https://service.example.com",
          measurement_id: "G-ABC123"
        ).call
      end
    end
  end
end
