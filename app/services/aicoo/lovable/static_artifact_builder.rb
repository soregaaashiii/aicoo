require "json"
require "fileutils"
require "find"
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
        :lockfile_generated,
        :framework,
        :build_started_at,
        :build_finished_at,
        :build_duration_ms,
        :build_stdout,
        :build_stderr,
        :build_exit_code,
        :output_candidates,
        :post_build_files,
        :temporary_config_adjustments
      )
      FORBIDDEN_LIFECYCLE_SCRIPTS = %w[
        preinstall install postinstall prepare prepublish prepublishOnly prebuild postbuild
      ].freeze
      BUILD_SCRIPTS = {
        "vite" => [ "vite build" ],
        "tanstack_start" => [ "vite build" ],
        "cra" => [ "react-scripts build" ],
        "next" => [ "next build" ],
        "astro" => [ "astro build" ],
        "remix" => [ "remix build", "remix vite:build" ]
      }.freeze
      FRAMEWORK_EXECUTABLES = {
        "vite" => "vite",
        "tanstack_start" => "vite",
        "cra" => "react-scripts",
        "next" => "next",
        "astro" => "astro",
        "remix" => "remix"
      }.freeze
      FRAMEWORK_OUTPUT_DIRECTORIES = {
        "vite" => %w[dist],
        "tanstack_start" => %w[dist/client .output/public],
        "cra" => %w[build],
        "next" => %w[out],
        "astro" => %w[dist],
        "remix" => %w[build/client public/build]
      }.freeze
      VITE_CONFIG_PATHS = %w[
        vite.config.ts vite.config.mts vite.config.cts
        vite.config.js vite.config.mjs vite.config.cjs
      ].freeze
      CONFIG_PATHS = [
        *VITE_CONFIG_PATHS,
        "next.config.js", "next.config.mjs", "next.config.ts",
        "astro.config.js", "astro.config.mjs", "astro.config.ts",
        "remix.config.js", "remix.config.mjs", "remix.config.ts"
      ].freeze
      OUTPUT_DIRECTORIES = %w[dist build out].freeze
      EXCLUDED_DISCOVERY_DIRECTORIES = %w[
        node_modules .git .cache cache tmp temp test tests spec fixtures
        examples example samples sample coverage src
      ].freeze
      PUBLIC_ASSET_EXTENSIONS = %w[
        .css .js .mjs .cjs .png .jpg .jpeg .gif .webp .svg .avif .ico
        .woff .woff2 .ttf .otf .json .webmanifest
      ].freeze
      MAX_OUTPUT_FILES = 400
      MAX_OUTPUT_BYTES = 12.megabytes
      MAX_DISCOVERY_DEPTH = 6
      MAX_DISCOVERY_FILES = 5_000
      MAX_DIAGNOSTIC_FILES = 500
      MAX_LOG_BYTES = 16.kilobytes
      MAX_HTML_BYTES = 2.megabytes

      class CommandRunner
        Result = Data.define(
          :stdout,
          :stderr,
          :success,
          :exit_code,
          :started_at,
          :finished_at,
          :duration_ms
        )

        def call(argv, chdir:, timeout_seconds:)
          stdout_text = +""
          stderr_text = +""
          status = nil
          started_at = Time.current
          monotonic_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
          finished_at = Time.current
          Result.new(
            stdout: stdout_text,
            stderr: stderr_text,
            success: status&.success?,
            exit_code: status&.exitstatus,
            started_at: started_at.iso8601,
            finished_at: finished_at.iso8601,
            duration_ms: elapsed_ms(monotonic_started_at)
          )
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

        def elapsed_ms(started_at)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
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
          return static_result(
            files: files_under("dist/"),
            build_type: "prebuilt_dist",
            output_directory: "dist/"
          )
        end
        if files.key?("index.html") && !files.key?("package.json")
          return static_result(
            files: static_source_files,
            build_type: "static_files",
            output_directory: "/"
          )
        end

        build_package
      end

      private

      attr_reader :files, :page_path, :command_runner

      def static_result(files:, build_type:, output_directory:)
        Result.new(
          files:,
          build_type:,
          warnings: [],
          package_manager: nil,
          commands: [],
          output_directory:,
          lockfile_generated: false,
          framework: "static",
          build_started_at: nil,
          build_finished_at: nil,
          build_duration_ms: nil,
          build_stdout: nil,
          build_stderr: nil,
          build_exit_code: nil,
          output_candidates: [ output_directory ],
          post_build_files: files.keys.sort.first(MAX_DIAGNOSTIC_FILES),
          temporary_config_adjustments: []
        )
      end

      def build_package
        package = parse_package_json
        framework = detect_framework(package)
        validate_package!(package, framework)
        package_manager = detect_package_manager
        diagnostics = {
          "package_manager" => package_manager,
          "framework" => framework,
          "commands" => [],
          "lockfile_generated" => false,
          "config_files" => CONFIG_PATHS.select { |path| files.key?(path) },
          "temporary_config_adjustments" => []
        }

        Dir.mktmpdir("aicoo-lovable-build") do |directory|
          write_source_files(directory)
          prepare_tanstack_static_build!(directory, framework, diagnostics)
          binary = resolved_package_manager_binary(package_manager)

          if lockfile_generation_required?(package_manager)
            generate_package_lock!(binary:, directory:, diagnostics:)
          end
          install_dependencies!(
            package_manager:,
            binary:,
            directory:,
            diagnostics:
          )
          validate_framework_executable!(directory, framework, diagnostics)

          build_result = run_build!(
            package_manager:,
            binary:,
            directory:,
            framework:,
            diagnostics:
          )
          record_post_build_diagnostics!(directory, diagnostics)

          output_directory = detect_output_directory(directory, framework, diagnostics)
          unless output_directory
            raise_build!(
              "static_build_output_missing",
              "buildは成功しましたが、公開可能なindex.htmlが見つかりませんでした。",
              diagnostics
            )
          end

          diagnostics["output_directory"] = display_output_directory(output_directory)
          output = read_output_files(File.join(directory, output_directory))
          warnings = if diagnostics["lockfile_generated"]
            [ "package-lock.jsonがなかったため一時生成しました" ]
          else
            []
          end

          Result.new(
            files: output,
            build_type: framework,
            warnings:,
            package_manager:,
            commands: diagnostics["commands"],
            output_directory: diagnostics["output_directory"],
            lockfile_generated: diagnostics["lockfile_generated"],
            framework:,
            build_started_at: diagnostics["build_started_at"],
            build_finished_at: diagnostics["build_finished_at"],
            build_duration_ms: diagnostics["build_duration_ms"],
            build_stdout: diagnostics["build_stdout"],
            build_stderr: diagnostics["build_stderr"],
            build_exit_code: diagnostics["build_exit_code"],
            output_candidates: diagnostics["output_candidates"],
            post_build_files: diagnostics["post_build_files"],
            temporary_config_adjustments: diagnostics["temporary_config_adjustments"]
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

      def detect_framework(package)
        dependencies = package.fetch("dependencies", {}).to_h.merge(package.fetch("devDependencies", {}).to_h)
        build_script = package.dig("scripts", "build").to_s.strip
        return "tanstack_start" if dependencies.key?("@tanstack/react-start")
        return "next" if dependencies.key?("next")
        return "astro" if dependencies.key?("astro")
        return "remix" if dependencies.key?("@remix-run/dev") || build_script.start_with?("remix ")
        return "cra" if dependencies.key?("react-scripts")
        return "vite" if dependencies.key?("vite")

        "unknown"
      end

      def validate_package!(package, framework)
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
        unless BUILD_SCRIPTS.fetch(framework, []).include?(build_script)
          raise UnsafeBuild.new(
            "安全に実行できるbuild scriptではありません: #{build_script}",
            code: "static_build_script_unsupported"
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
        if retry_generated_lock_platform_failure?(package_manager, result, diagnostics)
          diagnostics["temporary_config_adjustments"] <<
            "一時生成したpackage-lock.jsonのplatform metadataに合わせてnpm ciを再試行"
          result = execute_command(argv + [ "--force" ], directory:, diagnostics:)
        end
        return if result.success

        code = package_manager == "npm" ? "static_build_npm_ci_failed" : "static_build_dependency_install_failed"
        label = package_manager == "npm" ? "npm ci" : "#{package_manager} install"
        raise_build!(code, "#{label}に失敗しました: #{command_error(result)}", diagnostics)
      end

      def retry_generated_lock_platform_failure?(package_manager, result, diagnostics)
        package_manager == "npm" &&
          diagnostics["lockfile_generated"] == true &&
          !result.success &&
          "#{result.stdout}\n#{result.stderr}".match?(/\bEBADPLATFORM\b|Unsupported platform/i)
      end

      def validate_framework_executable!(directory, framework, diagnostics)
        executable = FRAMEWORK_EXECUTABLES.fetch(framework)
        path = File.join(directory, "node_modules", ".bin", executable)
        return if File.file?(path)

        raise_build!(
          "static_build_framework_executable_missing",
          "#{framework}のbuild executableを確認できません。",
          diagnostics
        )
      end

      def run_build!(package_manager:, binary:, directory:, framework:, diagnostics:)
        argv = build_command(package_manager:, binary:, framework:)
        result = execute_command(argv, directory:, diagnostics:)
        record_build_result!(result, diagnostics)
        return result if result.success

        raise_build!(
          "static_build_command_failed",
          "#{package_manager} run buildに失敗しました: #{command_error(result)}",
          diagnostics
        )
      end

      def build_command(package_manager:, binary:, framework:)
        argv = [ binary, "run", "build" ]
        if vite_base_argument?(framework)
          argv << "--" unless package_manager == "yarn"
          argv << "--base=#{page_path}"
        end
        argv
      end

      def vite_base_argument?(framework)
        return false unless framework.in?(%w[vite tanstack_start])
        return false unless package_json_build_script == "vite build"

        !vite_config_defines_base?
      end

      def package_json_build_script
        @package_json_build_script ||= JSON.parse(files.fetch("package.json")).dig("scripts", "build").to_s.strip
      end

      def vite_config_defines_base?
        VITE_CONFIG_PATHS.filter_map { |path| files[path] }.any? do |content|
          content.to_s.match?(/(?:\A|[,{]\s*)base\s*:/m)
        end
      end

      def execute_command(argv, directory:, diagnostics:)
        diagnostics["commands"] << display_command(argv)
        command_runner.call(argv, chdir: directory, timeout_seconds: 180)
      rescue UnsafeBuild => e
        raise UnsafeBuild.new(e.message, code: e.code, details: diagnostics.deep_dup)
      end

      def display_command(argv)
        argv.each_with_index.map do |value, index|
          index.zero? ? File.basename(value.to_s) : value.to_s
        end.join(" ")
      end

      def command_error(result)
        stderr = safe_log_text(result.stderr)
        stdout = safe_log_text(result.stdout)
        truncate_log(stderr.presence || stdout.presence || "終了ステータスが失敗でした。")
      end

      def record_build_result!(result, diagnostics)
        diagnostics["build_started_at"] = result_value(result, :started_at)
        diagnostics["build_finished_at"] = result_value(result, :finished_at)
        diagnostics["build_duration_ms"] = result_value(result, :duration_ms)
        diagnostics["build_stdout"] = truncate_log(result.stdout)
        diagnostics["build_stderr"] = truncate_log(result.stderr)
        diagnostics["build_exit_code"] = result_value(result, :exit_code)
      end

      def result_value(result, name)
        result.public_send(name) if result.respond_to?(name)
      end

      def truncate_log(value)
        text = safe_log_text(value)
        return text if text.bytesize <= MAX_LOG_BYTES

        text.byteslice(-MAX_LOG_BYTES, MAX_LOG_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub
      end

      def safe_log_text(value)
        value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      end

      def raise_build!(code, message, diagnostics)
        raise UnsafeBuild.new(
          message.to_s.last(1_200),
          code:,
          details: diagnostics.deep_dup
        )
      end

      def prepare_tanstack_static_build!(directory, framework, diagnostics)
        return unless framework == "tanstack_start"

        config_path = VITE_CONFIG_PATHS.find { |path| files.key?(path) }
        return unless config_path

        source = File.binread(File.join(directory, config_path))
        return unless source.include?("@lovable.dev/vite-tanstack-config")
        return if source.match?(/\bprerender\s*:/) || source.match?(/\bnitro\s*:/)
        return unless source.match?(/\btanstackStart\s*:\s*\{/)

        adjusted = source.sub(
          /export\s+default\s+defineConfig\s*\(\s*\{/,
          "\\0\n  nitro: false,"
        )
        adjusted = adjusted.sub(
          /\btanstackStart\s*:\s*\{/,
          "\\0\n    prerender: { enabled: true, crawlLinks: true, autoSubfolderIndex: true, failOnError: true },"
        )
        return if adjusted == source

        File.binwrite(File.join(directory, config_path), adjusted)
        diagnostics["temporary_config_adjustments"] << "Lovable TanStack Startを静的prerender用に一時設定"
      end

      def detect_output_directory(directory, framework, diagnostics)
        preferred = @preferred_output_directory
        if preferred.present? && valid_output_candidate?(directory, preferred)
          diagnostics["output_candidates"] = [ display_output_directory(preferred) ]
          return preferred
        end

        framework_directories = [
          *FRAMEWORK_OUTPUT_DIRECTORIES.fetch(framework, []),
          *OUTPUT_DIRECTORIES
        ].uniq
        framework_directories.each do |candidate|
          if valid_output_candidate?(directory, candidate)
            diagnostics["output_candidates"] = [ display_output_directory(candidate) ]
            return candidate
          end
        end

        candidates = discover_output_candidates(directory)
        diagnostics["output_candidates"] = candidates.map { |candidate| display_output_directory(candidate) }
        return candidates.one? ? candidates.first : nil if candidates.size <= 1

        scored = candidates.group_by { |candidate| output_candidate_score(directory, candidate) }
        best_score = scored.keys.max
        winners = scored.fetch(best_score)
        return winners.first if winners.one?

        raise_build!(
          "static_build_output_ambiguous",
          "build後に複数の公開候補が見つかり、自動判定できませんでした。",
          diagnostics
        )
      end

      def discover_output_candidates(directory)
        discover_index_files(directory).filter_map do |index_path|
          relative_directory = Pathname.new(File.dirname(index_path))
            .relative_path_from(Pathname.new(directory)).to_s
          relative_directory = "" if relative_directory == "."
          relative_directory if valid_output_candidate?(directory, relative_directory)
        end.uniq.sort
      end

      def discover_index_files(directory)
        values = []
        scanned_files = 0
        Find.find(directory) do |path|
          relative = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
          depth = relative == "." ? 0 : relative.split(File::SEPARATOR).size
          if File.directory?(path)
            if depth > MAX_DISCOVERY_DEPTH || excluded_discovery_directory?(relative)
              Find.prune
            end
            next
          end

          scanned_files += 1
          break if scanned_files > MAX_DISCOVERY_FILES
          values << path if File.basename(path) == "index.html"
        end
        values
      end

      def valid_output_candidate?(root, relative_directory)
        directory = File.join(root, relative_directory)
        index_path = File.join(directory, "index.html")
        return false unless File.file?(index_path)
        return false if excluded_discovery_directory?(relative_directory)
        return false if File.size(index_path) > MAX_HTML_BYTES

        html = File.binread(index_path)
        return false unless readable_html?(html)
        return false if development_template?(html)

        static_asset_files(directory).any? || html_references_public_asset?(html)
      rescue Errno::ENOENT, Errno::EACCES
        false
      end

      def readable_html?(html)
        text = html.to_s
        text.valid_encoding? && text.match?(/<!doctype\s+html|<html\b|<head\b|<body\b/i)
      end

      def development_template?(html)
        html.to_s.match?(%r{(?:src|href)=["']/?src/}i) ||
          html.to_s.include?("/@vite/client") ||
          html.to_s.match?(%r{(?:src|href)=["'][^"']+\.(?:ts|tsx)["']}i)
      end

      def html_references_public_asset?(html)
        html.to_s.scan(/(?:src|href)=["']([^"']+)["']/i).flatten.any? do |reference|
          clean = reference.split(/[?#]/, 2).first.to_s
          PUBLIC_ASSET_EXTENSIONS.include?(File.extname(clean).downcase)
        end
      end

      def static_asset_files(directory)
        Dir.children(directory).filter_map do |entry|
          path = File.join(directory, entry)
          next entry if File.directory?(path) && entry == "assets"
          next unless File.file?(path)
          next unless PUBLIC_ASSET_EXTENSIONS.include?(File.extname(path).downcase)

          entry
        end
      rescue Errno::ENOENT
        []
      end

      def output_candidate_score(root, relative_directory)
        directory = File.join(root, relative_directory)
        asset_directory_score = Dir.exist?(File.join(directory, "assets")) ? 10_000 : 0
        file_score = [ count_files(directory, limit: 1_000), 1_000 ].min
        generated_directory_score = relative_directory.present? ? 1_000 : 0

        asset_directory_score + generated_directory_score + file_score
      end

      def record_post_build_diagnostics!(directory, diagnostics)
        diagnostics["post_build_files"] = diagnostic_file_list(directory)
      end

      def diagnostic_file_list(directory)
        values = []
        Find.find(directory) do |path|
          relative = Pathname.new(path).relative_path_from(Pathname.new(directory)).to_s
          depth = relative == "." ? 0 : relative.split(File::SEPARATOR).size
          if File.directory?(path)
            if depth > 3 || excluded_discovery_directory?(relative)
              Find.prune
            end
            next
          end

          values << relative
          break if values.size >= MAX_DIAGNOSTIC_FILES
        end
        values.sort
      end

      def count_files(directory, limit:)
        count = 0
        Find.find(directory) do |path|
          next if File.directory?(path)

          count += 1
          break if count >= limit
        end
        count
      end

      def excluded_discovery_directory?(relative)
        relative.to_s.split(File::SEPARATOR).any? do |part|
          EXCLUDED_DISCOVERY_DIRECTORIES.include?(part.downcase)
        end
      end

      def display_output_directory(value)
        value.to_s.blank? ? "/" : "#{value.to_s.delete_suffix('/')}/"
      end

      def normalize_output_directory(value)
        normalized = value.to_s.tr("\\", "/").sub(%r{\A/+}, "").sub(%r{/+\z}, "")
        return if normalized.blank?
        return if normalized.split("/").any? { |part| part.blank? || part == ".." }
        return if excluded_discovery_directory?(normalized)

        normalized
      end

      def write_source_files(directory)
        files.each do |path, content|
          destination = safe_destination(directory, path)
          FileUtils.mkdir_p(File.dirname(destination))
          File.binwrite(destination, content)
        end
      end

      def read_output_files(directory)
        raise UnsafeBuild, "静的成果物directoryが生成されませんでした。" unless Dir.exist?(directory)

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
