require "test_helper"

module Aicoo
  module Lovable
    class StaticArtifactBuilderTest < ActiveSupport::TestCase
      test "keeps plain HTML CSS and JavaScript as static output" do
        result = StaticArtifactBuilder.new(
          files: {
            "index.html" => "<!doctype html><title>LP</title>",
            "styles.css" => "body{}",
            "app.js" => "console.log('lp')"
          },
          page_path: "/ai-reception"
        ).call

        assert_equal "static_files", result.build_type
        assert_equal %w[app.js index.html styles.css], result.files.keys.sort
      end

      test "builds Vite with ignored lifecycle scripts and AICOO fixed command" do
        runner = FakeViteRunner.new
        result = StaticArtifactBuilder.new(
          files: {
            "package.json" => JSON.generate(
              scripts: { build: "vite build" },
              devDependencies: { vite: "6.0.0" }
            ),
            "package-lock.json" => JSON.generate(lockfileVersion: 3, packages: {}),
            "index.html" => "<div id=\"root\"></div>",
            "src/main.js" => "document.querySelector('#root').textContent = 'LP'"
          },
          page_path: "/ai-reception",
          command_runner: runner,
          npm_binary: "/usr/bin/true"
        ).call

        assert_equal "vite", result.build_type
        assert result.files.key?("index.html")
        assert_equal "/usr/bin/true", runner.calls.first.first
        assert_includes runner.calls.first, "--ignore-scripts"
        assert_equal "vite", File.basename(runner.calls.second.first)
        assert_includes runner.calls.second, "/ai-reception/"
      end

      test "stops repositories with lifecycle scripts for manual repair" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          StaticArtifactBuilder.new(
            files: {
              "package.json" => JSON.generate(
                scripts: { build: "vite build", postinstall: "node steal.js" },
                devDependencies: { vite: "6.0.0" }
              ),
              "package-lock.json" => "{}"
            },
            page_path: "/lp"
          ).call
        end

        assert_includes error.message, "postinstall"
      end

      class FakeViteRunner
        Result = Data.define(:stdout, :stderr, :success)
        attr_reader :calls

        def initialize
          @calls = []
        end

        def call(argv, chdir:, timeout_seconds:)
          calls << argv
          if argv.include?("ci")
            vite = File.join(chdir, "node_modules", ".bin", "vite")
            FileUtils.mkdir_p(File.dirname(vite))
            File.write(vite, "#!/bin/sh\n")
            FileUtils.chmod(0o755, vite)
          else
            FileUtils.mkdir_p(File.join(chdir, "dist", "assets"))
            File.write(File.join(chdir, "dist", "index.html"), "<!doctype html><title>Built LP</title>")
            File.write(File.join(chdir, "dist", "assets", "app.js"), "console.log('built')")
          end
          Result.new(stdout: timeout_seconds.to_s, stderr: "", success: true)
        end
      end
    end
  end
end
