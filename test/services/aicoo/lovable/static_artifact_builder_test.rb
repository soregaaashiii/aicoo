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

        assert_equal "static_build_output_directory_missing", error.code
        assert_includes error.message, "静的成果物ディレクトリ"
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

      class FakeBuildRunner
        Result = Data.define(:stdout, :stderr, :success)

        attr_reader :commands, :working_directory

        def initialize(output_directory: "dist", output_directories: nil, fail_command: nil)
          @commands = []
          @output_directory = output_directory
          @output_directories = output_directories || [ output_directory ].compact
          @fail_command = fail_command
        end

        def call(argv, chdir:, timeout_seconds:)
          @working_directory = chdir
          commands << argv
          if argv.include?("--package-lock-only")
            return failure("lockfile failed") if @fail_command == :lockfile

            File.write(File.join(chdir, "package-lock.json"), JSON.generate(lockfileVersion: 3))
          elsif install_command?(argv)
            return failure("install failed") if @fail_command == :install

            vite = File.join(chdir, "node_modules", ".bin", "vite")
            FileUtils.mkdir_p(File.dirname(vite))
            File.write(vite, "#!/bin/sh\n")
            FileUtils.chmod(0o755, vite)
          elsif build_command?(argv)
            return failure("build failed") if @fail_command == :build

            @output_directories.each do |output_directory|
              FileUtils.mkdir_p(File.join(chdir, output_directory, "assets"))
              File.write(File.join(chdir, output_directory, "index.html"), "<!doctype html><title>Built LP</title>")
              File.write(File.join(chdir, output_directory, "assets", "app.js"), "console.log('built')")
            end
          end
          Result.new(stdout: timeout_seconds.to_s, stderr: "", success: true)
        end

        private

        def install_command?(argv)
          argv[1] == "ci" || (argv[1] == "install" && !argv.include?("--package-lock-only"))
        end

        def build_command?(argv)
          argv[1, 2] == %w[run build]
        end

        def failure(message)
          Result.new(stdout: "", stderr: message, success: false)
        end
      end
    end
  end
end
