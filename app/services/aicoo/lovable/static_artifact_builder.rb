require "json"
require "fileutils"
require "open3"
require "pathname"
require "timeout"
require "tmpdir"

module Aicoo
  module Lovable
    class StaticArtifactBuilder
      class UnsafeBuild < StandardError
        attr_reader :code, :details

        def initialize(message, code: "static_build_failed", details: {})
          @code = code
          @details = details
          super(message)
        end
      end

      Result = Data.define(
        :files,
        :build_type,
        :warnings,
        :package_manager,
        :commands,
        :output_directory,
        :lockfile_generated
      )
      FORBIDDEN_LIFECYCLE_SCRIPTS = %w[
        preinstall install postinstall prepare prepublish prepublishOnly
      ].freeze
      OUTPUT_DIRECTORIES = %w[dist build out].freeze
      MAX_OUTPUT_FILES = 400
      MAX_OUTPUT_BYTES = 12.megabytes

      class CommandRunner
        Result = Data.define(:stdout, :stderr, :success)

        def call(argv, chdir:, timeout_seconds:)
          stdout_text = +""
          stderr_text = +""
          status = nil
          Open3.popen3(safe_environment(chdir), *argv, chdir:) do |stdin, stdout, stderr, wait_thread|
            stdin.close
            readers = [
              Thread.new { stdout_text << stdout.read },
              Thread.new { stderr_text << stderr.read }
            ]
            begin
              Timeout.timeout(timeout_seconds) { status = wait_thread.value }
            rescue Timeout::Error
              Process.kill("TERM", wait_thread.pid)
              raise UnsafeBuild.new(
                "静的buildが#{timeout_seconds}秒でタイムアウトしました。",
                code: "static_build_timeout"
              )
            ensure
              readers.each(&:join)
            end
          end
          Result.new(stdout: stdout_text, stderr: stderr_text, success: status&.success?)
        end

        private

        def safe_environment(chdir)
          {
            "HOME" => chdir,
            "NODE_ENV" => "production",
            "CI" => "1",
            "PATH" => ENV.fetch("PATH", "/usr/local/bin:/usr/bin:/bin")
          }
        end
      end

      def initialize(
        files:,
        page_path:,
        command_runner: CommandRunner.new,
        npm_binary: nil,
        pnpm_binary: nil,
        yarn_binary: nil,
        output_directory: nil
      )
        @files = normalize_source_files(files)
        @page_path = normalize_page_path(page_path)
        @command_runner = command_runner
        @preferred_output_directory = normalize_output_directory(output_directory)
        @package_manager_binaries = {
          "npm" => npm_binary,
          "pnpm" => pnpm_binary,
          "yarn" => yarn_binary
        }
      end

      def call
        if files.key?("dist/index.html")
          return Result.new(
            files: files_under("dist/"),
            build_type: "prebuilt_dist",
            warnings: [],
            package_manager: nil,
            commands: [],
            output_directory: "dist/",
            lockfile_generated: false
          )
        end
        if files.key?("index.html") && !files.key?("package.json")
          return Result.new(
            files: static_source_files,
            build_type: "static_files",
            warnings: [],
            package_manager: nil,
            commands: [],
            output_directory: "/",
            lockfile_generated: false
          )
        end

        build_package
      end

      private

      attr_reader :files, :page_path, :command_runner

      def build_package
        package = parse_package_json
        validate_vite_package!(package)
        package_manager = detect_package_manager
        diagnostics = {
          "package_manager" => package_manager,
          "commands" => [],
          "lockfile_generated" => false
        }

        Dir.mktmpdir("aicoo-lovable-build") do |directory|
          write_source_files(directory)
          binary = resolved_package_manager_binary(package_manager)

          if lockfile_generation_required?(package_manager)
            generate_package_lock!(
              binary:,
              directory:,
              diagnostics:
            )
          end
          install_dependencies!(
            package_manager:,
            binary:,
            directory:,
            diagnostics:
          )

          vite = File.join(directory, "node_modules", ".bin", "vite")
          unless File.file?(vite)
            raise_build!(
              "static_build_vite_missing",
              "許可されたVite executableを確認できません。",
              diagnostics
            )
          end

          run_build!(
            package_manager:,
            binary:,
            directory:,
            diagnostics:
          )

          output_directory = detect_output_directory(directory)
          unless output_directory
            raise_build!(
              "static_build_output_directory_missing",
              "buildコマンドは成功しましたが、静的成果物ディレクトリ（dist / build / out）が見つかりません。",
              diagnostics
            )
          end
          diagnostics["output_directory"] = "#{output_directory}/"
          output = read_output_files(File.join(directory, output_directory))
          unless output.key?("index.html")
            raise_build!(
              "static_build_output_missing",
              "buildコマンドは成功しましたが、#{output_directory}/index.htmlがありません。",
              diagnostics
            )
          end

          warnings = if diagnostics["lockfile_generated"]
            [ "package-lock.jsonがなかったため一時生成しました" ]
          else
            []
          end
          Result.new(
            files: output,
            build_type: "vite",
            warnings:,
            package_manager:,
            commands: diagnostics["commands"],
            output_directory: diagnostics["output_directory"],
            lockfile_generated: diagnostics["lockfile_generated"]
          )
        end
      end

      def parse_package_json
        unless files.key?("package.json")
          raise UnsafeBuild.new(
            "package.jsonがありません。",
            code: "static_build_package_json_missing"
          )
        end

        JSON.parse(files.fetch("package.json"))
      rescue JSON::ParserError
        raise UnsafeBuild.new(
          "package.jsonを解析できません。",
          code: "static_build_package_json_invalid"
        )
      end

      def validate_vite_package!(package)
        scripts = package.fetch("scripts", {}).to_h
        dangerous = FORBIDDEN_LIFECYCLE_SCRIPTS.select { |name| scripts[name].present? }
        if dangerous.any?
          raise UnsafeBuild.new(
            "危険なlifecycle scriptを検出しました: #{dangerous.join(', ')}",
            code: "static_build_unsafe_lifecycle_script"
          )
        end

        build_script = scripts["build"].to_s.strip
        if build_script.blank?
          raise UnsafeBuild.new(
            "package.jsonにbuild scriptがありません。",
            code: "static_build_script_missing"
          )
        end
        if build_script != "vite build"
          raise UnsafeBuild.new(
            "許可されていないbuild scriptです。許可されるのはvite buildだけです。",
            code: "static_build_script_unsupported"
          )
        end
        dependencies = package.fetch("dependencies", {}).to_h.merge(package.fetch("devDependencies", {}).to_h)
        unless dependencies.key?("vite")
          raise UnsafeBuild.new(
            "Vite dependencyがないため安全な静的build対象ではありません。",
            code: "static_build_vite_missing"
          )
        end
      end

      def detect_package_manager
        return "pnpm" if files.key?("pnpm-lock.yaml")
        return "yarn" if files.key?("yarn.lock")
        return "npm" if files.key?("package-lock.json")

        "npm"
      end

      def lockfile_generation_required?(package_manager)
        package_manager == "npm" && !files.key?("package-lock.json")
      end

      def generate_package_lock!(binary:, directory:, diagnostics:)
        argv = [
          binary,
          "install",
          "--package-lock-only",
          "--ignore-scripts",
          "--include=dev",
          "--no-audit",
          "--no-fund"
        ]
        result = execute_command(argv, directory:, diagnostics:)
        unless result.success
          raise_build!(
            "static_build_lockfile_generation_failed",
            "package-lock.jsonの一時生成に失敗しました: #{command_error(result)}",
            diagnostics
          )
        end
        unless File.file?(File.join(directory, "package-lock.json"))
          raise_build!(
            "static_build_lockfile_generation_failed",
            "package-lock.jsonの一時生成に失敗しました: 生成後もファイルを確認できません。",
            diagnostics
          )
        end

        diagnostics["lockfile_generated"] = true
      end

      def install_dependencies!(package_manager:, binary:, directory:, diagnostics:)
        argv = case package_manager
        when "pnpm"
          [ binary, "install", "--frozen-lockfile", "--ignore-scripts", "--prod=false" ]
        when "yarn"
          [ binary, "install", "--frozen-lockfile", "--ignore-scripts", "--production=false" ]
        else
          [ binary, "ci", "--ignore-scripts", "--include=dev", "--no-audit", "--no-fund" ]
        end
        result = execute_command(argv, directory:, diagnostics:)
        return if result.success

        code = package_manager == "npm" ? "static_build_npm_ci_failed" : "static_build_dependency_install_failed"
        label = package_manager == "npm" ? "npm ci" : "#{package_manager} install"
        raise_build!(code, "#{label}に失敗しました: #{command_error(result)}", diagnostics)
      end

      def run_build!(package_manager:, binary:, directory:, diagnostics:)
        argv = [ binary, "run", "build" ]
        argv << "--" unless package_manager == "yarn"
        argv.concat([ "--base", "#{page_path.delete_suffix('/')}/" ])
        result = execute_command(argv, directory:, diagnostics:)
        return if result.success

        raise_build!(
          "static_build_command_failed",
          "#{package_manager} run buildに失敗しました: #{command_error(result)}",
          diagnostics
        )
      end

      def execute_command(argv, directory:, diagnostics:)
        diagnostics["commands"] << display_command(argv)
        command_runner.call(argv, chdir: directory, timeout_seconds: 180)
      rescue UnsafeBuild => e
        raise UnsafeBuild.new(e.message, code: e.code, details: diagnostics.deep_dup)
      end

      def display_command(argv)
        argv.map { |value| File.basename(value.to_s) == value.to_s ? value.to_s : File.basename(value.to_s) }.join(" ")
      end

      def command_error(result)
        result.stderr.to_s.presence || result.stdout.to_s.presence || "終了ステータスが失敗でした。"
      end

      def raise_build!(code, message, diagnostics)
        raise UnsafeBuild.new(
          message.to_s.last(1_200),
          code:,
          details: diagnostics.deep_dup
        )
      end

      def detect_output_directory(directory)
        [ @preferred_output_directory, *OUTPUT_DIRECTORIES ].compact.uniq.find do |name|
          Dir.exist?(File.join(directory, name))
        end
      end

      def normalize_output_directory(value)
        normalized = value.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
        normalized if normalized.in?(OUTPUT_DIRECTORIES)
      end

      def write_source_files(directory)
        files.each do |path, content|
          destination = safe_destination(directory, path)
          FileUtils.mkdir_p(File.dirname(destination))
          File.binwrite(destination, content)
        end
      end

      def read_output_files(directory)
        raise UnsafeBuild, "dist directoryが生成されませんでした。" unless Dir.exist?(directory)

        paths = Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
        raise UnsafeBuild, "静的成果物が#{MAX_OUTPUT_FILES}件を超えています。" if paths.size > MAX_OUTPUT_FILES
        total_bytes = paths.sum { |path| File.size(path) }
        raise UnsafeBuild, "静的成果物が#{MAX_OUTPUT_BYTES / 1.megabyte}MBを超えています。" if total_bytes > MAX_OUTPUT_BYTES

        paths.to_h do |path|
          relative = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
          [ relative, File.binread(path) ]
        end
      end

      def files_under(prefix)
        files.filter_map do |path, content|
          next unless path.start_with?(prefix)

          [ path.delete_prefix(prefix), content ]
        end.to_h
      end

      def static_source_files
        files.reject do |path, _content|
          path == "package.json" || path == "package-lock.json" || path.start_with?(".github/")
        end
      end

      def normalize_source_files(values)
        values.to_h.to_h do |path, content|
          normalized = path.to_s.tr("\\", "/").sub(%r{\A/+}, "")
          parts = normalized.split("/")
          raise UnsafeBuild, "生成結果に不正なpathがあります。" if normalized.blank? || parts.include?("..")
          if normalized.match?(%r{\A(?:\.env(?:\.|$)|supabase/|functions/|api/|server/|backend/|node_modules/)}i)
            raise UnsafeBuild, "静的LPへ取り込めないbackend・秘密情報pathがあります: #{normalized}"
          end

          [ normalized, content.to_s.b ]
        end
      end

      def normalize_page_path(value)
        path = "/#{value.to_s.sub(%r{\A/+}, '').sub(%r{/+\z}, '')}/"
        path == "//" ? "/" : path
      end

      def safe_destination(root, relative_path)
        destination = File.expand_path(relative_path, root)
        root_path = File.expand_path(root)
        unless destination.start_with?("#{root_path}/")
          raise UnsafeBuild, "生成結果に作業directory外のpathがあります。"
        end

        destination
      end

      def resolved_package_manager_binary(package_manager)
        configured = @package_manager_binaries.fetch(package_manager).presence
        return configured if configured.present? && File.executable?(configured)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, package_manager)
          return candidate if File.executable?(candidate)
        end
        raise UnsafeBuild.new(
          "安全な静的buildに必要な#{package_manager}が実行環境にありません。",
          code: "static_build_package_manager_missing",
          details: { "package_manager" => package_manager }
        )
      end
    end
  end
end
