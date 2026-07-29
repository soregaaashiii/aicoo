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
        assert_equal "/", result.output_directory
        assert_equal %w[app.js index.html styles.css], result.files.keys.sort
      end

      test "uses npm ci when package lock exists" do
        runner = FakeBuildRunner.new

        result = build(files: package_files("package-lock.json" => "{}"), runner:)

        assert_equal "npm", result.package_manager
        assert_equal false, result.lockfile_generated
        assert runner.commands.any? { |argv| argv[1] == "ci" }
        assert_not runner.commands.any? { |argv| argv.include?("--package-lock-only") }
        assert runner.commands.any? { |argv| argv[1, 2] == %w[run build] }
      end

      test "keeps the repository Vite config for the build" do
        runner = FakeBuildRunner.new
        files = package_files(
          "package-lock.json" => "{}",
          "vite.config.ts" => "export default { build: { outDir: 'dist' } }"
        )

        build(files:, runner:)

        build_command = runner.commands.find { |argv| argv[1, 2] == %w[run build] }
        assert_not_includes build_command, "--config"
        assert_includes build_command, "--base=/ai-reception/"
        assert_equal files["vite.config.ts"], "export default { build: { outDir: 'dist' } }"
      end

      test "does not add Vite base when the repository config already defines it" do
        runner = FakeBuildRunner.new
        files = package_files(
          "package-lock.json" => "{}",
          "vite.config.ts" => "export default { base: '/saved/', build: { outDir: 'dist' } }"
        )

        build(files:, runner:)

        build_command = runner.commands.find { |argv| argv[1, 2] == %w[run build] }
        assert_not build_command.any? { |argument| argument.start_with?("--base=") }
      end

      test "generates a temporary package lock before npm ci" do
        runner = FakeBuildRunner.new
        source_files = package_files

        result = build(files: source_files, runner:)

        assert_equal "npm", result.package_manager
        assert_equal true, result.lockfile_generated
        assert_includes result.warnings, "package-lock.jsonがなかったため一時生成しました"
        assert_equal "install", runner.commands[0][1]
        assert_includes runner.commands[0], "--package-lock-only"
        assert_includes runner.commands[0], "--ignore-scripts"
        assert_equal "ci", runner.commands[1][1]
        assert_includes runner.commands[1], "--ignore-scripts"
        assert_equal %w[run build], runner.commands[2][1, 2]
      end

      test "uses pnpm when pnpm lock exists" do
        runner = FakeBuildRunner.new

        result = build(files: package_files("pnpm-lock.yaml" => "lockfileVersion: '9.0'"), runner:)

        assert_equal "pnpm", result.package_manager
        assert_equal "install", runner.commands[0][1]
        assert_includes runner.commands[0], "--frozen-lockfile"
        assert_includes runner.commands[0], "--ignore-scripts"
        assert_equal %w[run build], runner.commands[1][1, 2]
      end

      test "uses yarn when yarn lock exists" do
        runner = FakeBuildRunner.new

        result = build(files: package_files("yarn.lock" => "# yarn lockfile v1"), runner:)

        assert_equal "yarn", result.package_manager
        assert_equal "install", runner.commands[0][1]
        assert_includes runner.commands[0], "--frozen-lockfile"
        assert_includes runner.commands[0], "--ignore-scripts"
        assert_equal %w[run build], runner.commands[1][1, 2]
      end

      test "fails clearly when package json is missing" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(files: { "src/main.js" => "console.log('lp')" }, runner: FakeBuildRunner.new)
        end

        assert_equal "static_build_package_json_missing", error.code
        assert_equal "package.jsonがありません。", error.message
      end

      test "fails clearly when build script is missing" do
        files = package_files(
          "package.json" => JSON.generate(devDependencies: { vite: "6.0.0" }),
          "package-lock.json" => "{}"
        )

        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(files:, runner: FakeBuildRunner.new)
        end

        assert_equal "static_build_script_missing", error.code
        assert_equal "package.jsonにbuild scriptがありません。", error.message
      end

      test "uses dist output first" do
        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner: FakeBuildRunner.new(output_directory: "dist")
        )

        assert_equal "dist/", result.output_directory
        assert result.files.key?("index.html")
      end

      test "uses build output when dist is absent" do
        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner: FakeBuildRunner.new(output_directory: "build")
        )

        assert_equal "build/", result.output_directory
        assert result.files.key?("index.html")
      end

      test "uses out output when dist and build are absent" do
        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner: FakeBuildRunner.new(output_directory: "out")
        )

        assert_equal "out/", result.output_directory
        assert result.files.key?("index.html")
      end

      test "detects a valid generated index outside standard output directories" do
        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner: FakeBuildRunner.new(
            output_directory: nil,
            build_files: {
              "site/public/index.html" => built_html("assets/app.js"),
              "site/public/assets/app.js" => "console.log('built')"
            }
          )
        )

        assert_equal "site/public/", result.output_directory
        assert result.files.key?("index.html")
      end

      test "uses a repository root static site when it is publicly complete" do
        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner: FakeBuildRunner.new(
            output_directory: nil,
            build_files: {
              "index.html" => built_html("assets/app.js"),
              "assets/app.js" => "console.log('built')"
            }
          )
        )

        assert_equal "/", result.output_directory
      end

      test "does not publish a source index template" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(
              output_directory: nil,
              build_files: {
                "src/index.html" => built_html("assets/app.js"),
                "src/assets/app.js" => "console.log('source')"
              }
            )
          )
        end

        assert_equal "static_build_output_missing", error.code
        assert_empty error.details["output_candidates"]
      end

      test "does not publish an index from node modules" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(
              output_directory: nil,
              build_files: {
                "node_modules/example/index.html" => built_html("assets/app.js"),
                "node_modules/example/assets/app.js" => "console.log('dependency')"
              }
            )
          )
        end

        assert_equal "static_build_output_missing", error.code
      end

      test "fails with candidate details when multiple outputs are equally valid" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(
              output_directory: nil,
              build_files: {
                "site-a/index.html" => built_html("assets/app.js"),
                "site-a/assets/app.js" => "console.log('a')",
                "site-b/index.html" => built_html("assets/app.js"),
                "site-b/assets/app.js" => "console.log('b')"
              }
            )
          )
        end

        assert_equal "static_build_output_ambiguous", error.code
        assert_equal %w[site-a/ site-b/], error.details["output_candidates"]
      end

      test "prefers a saved output directory when it exists" do
        runner = FakeBuildRunner.new(output_directories: %w[dist build])

        result = build(
          files: package_files("package-lock.json" => "{}"),
          runner:,
          output_directory: "build/"
        )

        assert_equal "build/", result.output_directory
      end

      test "fails clearly when the build output directory is absent" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(output_directory: nil)
          )
        end

        assert_equal "static_build_output_missing", error.code
        assert_includes error.message, "公開可能なindex.html"
      end

      test "fails clearly when temporary package lock generation fails" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files,
            runner: FakeBuildRunner.new(fail_command: :lockfile)
          )
        end

        assert_equal "static_build_lockfile_generation_failed", error.code
        assert_includes error.message, "package-lock.jsonの一時生成"
      end

      test "fails clearly when npm ci fails" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(fail_command: :install)
          )
        end

        assert_equal "static_build_npm_ci_failed", error.code
        assert_includes error.message, "npm ci"
      end

      test "fails clearly when package build fails" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files("package-lock.json" => "{}"),
            runner: FakeBuildRunner.new(fail_command: :build)
          )
        end

        assert_equal "static_build_command_failed", error.code
        assert_includes error.message, "npm run build"
      end

      test "does not write the generated package lock back to source files" do
        runner = FakeBuildRunner.new
        source_files = package_files

        build(files: source_files, runner:)

        assert_not source_files.key?("package-lock.json")
        assert_not Dir.exist?(runner.working_directory)
      end

      test "does not add Vite base to a Next static export build" do
        runner = FakeBuildRunner.new(output_directory: "out")

        result = build(files: next_package_files, runner:)

        build_command = runner.commands.find { |argv| argv[1, 2] == %w[run build] }
        assert_equal "next", result.framework
        assert_not build_command.any? { |argument| argument.start_with?("--base=") }
      end

      test "uses the CRA build directory without Vite arguments" do
        runner = FakeBuildRunner.new(output_directory: "build")
        files = {
          "package.json" => JSON.generate(
            scripts: { build: "react-scripts build" },
            dependencies: { "react-scripts": "5.0.1" }
          ),
          "package-lock.json" => "{}"
        }

        result = build(files:, runner:)

        build_command = runner.commands.find { |argv| argv[1, 2] == %w[run build] }
        assert_equal "cra", result.framework
        assert_equal "build/", result.output_directory
        assert_not build_command.any? { |argument| argument.start_with?("--base=") }
      end

      test "uses the Astro dist directory without Vite arguments" do
        runner = FakeBuildRunner.new(output_directory: "dist")
        files = {
          "package.json" => JSON.generate(
            scripts: { build: "astro build" },
            dependencies: { astro: "5.0.0" }
          ),
          "package-lock.json" => "{}"
        }

        result = build(files:, runner:)

        build_command = runner.commands.find { |argv| argv[1, 2] == %w[run build] }
        assert_equal "astro", result.framework
        assert_equal "dist/", result.output_directory
        assert_not build_command.any? { |argument| argument.start_with?("--base=") }
      end

      test "records stdout stderr exit code timestamps and generated files" do
        runner = FakeBuildRunner.new(
          stdout: "vite build completed",
          stderr: "vite warning",
          exit_code: 0
        )

        result = build(files: package_files("package-lock.json" => "{}"), runner:)

        assert_equal "vite build completed", result.build_stdout
        assert_equal "vite warning", result.build_stderr
        assert_equal 0, result.build_exit_code
        assert_equal "2026-07-30T00:00:00Z", result.build_started_at
        assert_equal "2026-07-30T00:00:01Z", result.build_finished_at
        assert_equal 1_000, result.build_duration_ms
        assert_includes result.post_build_files, "dist/index.html"
      end

      test "temporarily enables static prerender for the Lovable TanStack config" do
        runner = FakeBuildRunner.new(
          output_directory: nil,
          build_files: {
            "dist/client/index.html" => built_html("assets/app.js"),
            "dist/client/assets/app.js" => "console.log('built')"
          }
        )
        source_config = <<~TS
          // Example only: defineConfig({ vite: { ... } })
          import { defineConfig } from "@lovable.dev/vite-tanstack-config";
          export default defineConfig({
            tanstackStart: {
              server: { entry: "server" },
            },
          });
        TS
        files = package_files(
          "package.json" => JSON.generate(
            scripts: { build: "vite build" },
            dependencies: { "@tanstack/react-start": "1.0.0" },
            devDependencies: {
              "@lovable.dev/vite-tanstack-config": "2.7.6",
              vite: "8.0.0"
            }
          ),
          "package-lock.json" => "{}",
          "vite.config.ts" => source_config
        )

        result = build(files:, runner:)

        assert_equal "tanstack_start", result.framework
        assert_equal "dist/client/", result.output_directory
        assert_includes result.temporary_config_adjustments,
          "Lovable TanStack Startを静的prerender用に一時設定"
        assert_includes runner.config_during_build, "nitro: false"
        assert_includes runner.config_during_build, "prerender:"
        assert_equal source_config, files["vite.config.ts"]
      end

      test "keeps lifecycle scripts disabled" do
        error = assert_raises(StaticArtifactBuilder::UnsafeBuild) do
          build(
            files: package_files(
              "package.json" => JSON.generate(
                scripts: { build: "vite build", postinstall: "node steal.js" },
                devDependencies: { vite: "6.0.0" }
              ),
              "package-lock.json" => "{}"
            ),
            runner: FakeBuildRunner.new
          )
        end

        assert_equal "static_build_unsafe_lifecycle_script", error.code
        assert_includes error.message, "postinstall"
      end

      private

      def build(files:, runner:, output_directory: nil)
        StaticArtifactBuilder.new(
          files:,
          page_path: "/ai-reception",
          command_runner: runner,
          npm_binary: "/usr/bin/true",
          pnpm_binary: "/usr/bin/true",
          yarn_binary: "/usr/bin/true",
          output_directory:
        ).call
      end

      def package_files(overrides = {})
        {
          "package.json" => JSON.generate(
            scripts: { build: "vite build" },
            devDependencies: { vite: "6.0.0" }
          ),
          "index.html" => "<div id=\"root\"></div>",
          "src/main.js" => "document.querySelector('#root').textContent = 'LP'"
        }.merge(overrides)
      end

      def next_package_files
        {
          "package.json" => JSON.generate(
            scripts: { build: "next build" },
            dependencies: { next: "15.0.0" }
          ),
          "package-lock.json" => "{}"
        }
      end

      def built_html(script_path)
        "<!doctype html><html><head></head><body><script src=\"#{script_path}\"></script></body></html>"
      end

      class FakeBuildRunner
        Result = StaticArtifactBuilder::CommandRunner::Result

        attr_reader :commands, :working_directory, :config_during_build

        def initialize(
          output_directory: "dist",
          output_directories: nil,
          build_files: nil,
          fail_command: nil,
          stdout: "build stdout",
          stderr: "",
          exit_code: 0
        )
          @commands = []
          @output_directory = output_directory
          @output_directories = output_directories || [ output_directory ].compact
          @build_files = build_files
          @fail_command = fail_command
          @stdout = stdout
          @stderr = stderr
          @exit_code = exit_code
        end

        def call(argv, chdir:, timeout_seconds:)
          @working_directory = chdir
          commands << argv
          if argv.include?("--package-lock-only")
            return failure("lockfile failed") if @fail_command == :lockfile

            File.write(File.join(chdir, "package-lock.json"), JSON.generate(lockfileVersion: 3))
          elsif install_command?(argv)
            return failure("install failed") if @fail_command == :install

            %w[vite next astro remix react-scripts].each do |executable|
              path = File.join(chdir, "node_modules", ".bin", executable)
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, "#!/bin/sh\n")
              FileUtils.chmod(0o755, path)
            end
          elsif build_command?(argv)
            return failure("build failed") if @fail_command == :build

            config_path = File.join(chdir, "vite.config.ts")
            @config_during_build = File.read(config_path) if File.file?(config_path)
            if @build_files
              @build_files.each do |relative_path, content|
                path = File.join(chdir, relative_path)
                FileUtils.mkdir_p(File.dirname(path))
                File.binwrite(path, content)
              end
            else
              @output_directories.each do |output_directory|
                FileUtils.mkdir_p(File.join(chdir, output_directory, "assets"))
                File.write(
                  File.join(chdir, output_directory, "index.html"),
                  "<!doctype html><html><body><script src=\"assets/app.js\"></script></body></html>"
                )
                File.write(File.join(chdir, output_directory, "assets", "app.js"), "console.log('built')")
              end
            end
          end
          Result.new(
            stdout: build_command?(argv) ? @stdout : timeout_seconds.to_s,
            stderr: build_command?(argv) ? @stderr : "",
            success: true,
            exit_code: @exit_code,
            started_at: "2026-07-30T00:00:00Z",
            finished_at: "2026-07-30T00:00:01Z",
            duration_ms: 1_000
          )
        end

        private

        def install_command?(argv)
          argv[1] == "ci" || (argv[1] == "install" && !argv.include?("--package-lock-only"))
        end

        def build_command?(argv)
          argv[1, 2] == %w[run build]
        end

        def failure(message)
          Result.new(
            stdout: "",
            stderr: message,
            success: false,
            exit_code: 1,
            started_at: "2026-07-30T00:00:00Z",
            finished_at: "2026-07-30T00:00:01Z",
            duration_ms: 1_000
          )
        end
      end
    end
  end
end
