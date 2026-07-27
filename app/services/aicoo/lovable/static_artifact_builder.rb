require "json"
require "fileutils"
require "open3"
require "pathname"
require "timeout"
require "tmpdir"

module Aicoo
  module Lovable
    class StaticArtifactBuilder
      class UnsafeBuild < StandardError; end

      Result = Data.define(:files, :build_type, :warnings)
      FORBIDDEN_LIFECYCLE_SCRIPTS = %w[
        preinstall install postinstall prepare prepublish prepublishOnly
      ].freeze
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
              raise UnsafeBuild, "静的buildが#{timeout_seconds}秒でタイムアウトしました。"
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

      def initialize(files:, page_path:, command_runner: CommandRunner.new, npm_binary: nil)
        @files = normalize_source_files(files)
        @page_path = normalize_page_path(page_path)
        @command_runner = command_runner
        @npm_binary = npm_binary
      end

      def call
        return Result.new(files: files_under("dist/"), build_type: "prebuilt_dist", warnings: []) if files.key?("dist/index.html")
        return Result.new(files: static_source_files, build_type: "static_files", warnings: []) if files.key?("index.html") && !files.key?("package.json")

        build_vite
      end

      private

      attr_reader :files, :page_path, :command_runner

      def build_vite
        package = parse_package_json
        validate_vite_package!(package)
        raise UnsafeBuild, "package-lock.jsonがないため、安全なnpm ciを実行できません。" unless files.key?("package-lock.json")

        Dir.mktmpdir("aicoo-lovable-build") do |directory|
          write_source_files(directory)
          config_path = File.join(directory, "aicoo.vite.config.mjs")
          File.write(config_path, safe_vite_config)
          npm = resolved_npm_binary
          install = command_runner.call(
            [ npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund" ],
            chdir: directory,
            timeout_seconds: 180
          )
          raise UnsafeBuild, "npm ciに失敗しました: #{install.stderr.to_s.last(1_000)}" unless install.success

          vite = File.join(directory, "node_modules", ".bin", "vite")
          raise UnsafeBuild, "許可されたVite executableを確認できません。" unless File.file?(vite)

          build = command_runner.call(
            [ vite, "build", "--config", config_path, "--base", "#{page_path.delete_suffix('/')}/" ],
            chdir: directory,
            timeout_seconds: 180
          )
          raise UnsafeBuild, "Vite buildに失敗しました: #{build.stderr.to_s.last(1_000)}" unless build.success

          output = read_output_files(File.join(directory, "dist"))
          raise UnsafeBuild, "Vite build後にdist/index.htmlがありません。" unless output.key?("index.html")

          Result.new(files: output, build_type: "vite", warnings: [])
        end
      end

      def parse_package_json
        JSON.parse(files.fetch("package.json"))
      rescue JSON::ParserError
        raise UnsafeBuild, "package.jsonを解析できません。"
      end

      def validate_vite_package!(package)
        scripts = package.fetch("scripts", {}).to_h
        dangerous = FORBIDDEN_LIFECYCLE_SCRIPTS.select { |name| scripts[name].present? }
        raise UnsafeBuild, "危険なlifecycle scriptを検出しました: #{dangerous.join(', ')}" if dangerous.any?

        build_script = scripts["build"].to_s.strip
        if build_script.present? && build_script != "vite build"
          raise UnsafeBuild, "許可されていないbuild scriptです。許可されるのはvite buildだけです。"
        end
        dependencies = package.fetch("dependencies", {}).to_h.merge(package.fetch("devDependencies", {}).to_h)
        raise UnsafeBuild, "Vite dependencyがないため安全な静的build対象ではありません。" unless dependencies.key?("vite")
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

      def safe_vite_config
        <<~JAVASCRIPT
          import { defineConfig } from "vite";
          export default defineConfig({
            plugins: [],
            build: { outDir: "dist", emptyOutDir: true }
          });
        JAVASCRIPT
      end

      def resolved_npm_binary
        configured = @npm_binary.presence
        return configured if configured.present? && File.executable?(configured)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, "npm")
          return candidate if File.executable?(candidate)
        end
        raise UnsafeBuild, "安全なVite buildに必要なnpmが実行環境にありません。"
      end
    end
  end
end
