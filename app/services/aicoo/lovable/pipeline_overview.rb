module Aicoo
  module Lovable
    class PipelineOverview
      Diagnostic = Data.define(:label, :value, :url)
      Stage = Data.define(:number, :key, :label, :status, :timestamp, :detail, :diagnostics)
      HistoryEntry = Data.define(:timestamp, :label, :detail)

      STAGE_DEFINITIONS = [
        [ :landing_page, "LP作成" ],
        [ :approval, "承認" ],
        [ :generate, "Lovable" ],
        [ :github_source_push, "GitHub Push" ],
        [ :webhook, "Webhook" ],
        [ :artifact_fetch, "成果物取得" ],
        [ :static_build, "静的build" ],
        [ :publication_push, "aicoo-lp Push" ],
        [ :cloudflare, "Cloudflare" ],
        [ :http_verification, "HTTP200確認" ],
        [ :ga4, "GA4" ],
        [ :gsc, "GSC" ],
        [ :learning, "Learning" ]
      ].freeze

      STATUS_STAGE_INDEX = {
        "prompt_pending" => 2,
        "prompt_ready" => 2,
        "lovable_pending" => 2,
        "waiting_approval" => 2,
        "lovable_handoff_ready" => 3,
        "lovable_generation_started" => 3,
        "lovable_generation_waiting" => 3,
        "preview_ready" => 4,
        "lovable_result_waiting" => 4,
        "github_webhook_waiting" => 4,
        "github_webhook_received" => 6,
        "artifact_fetching" => 6,
        "lovable_result_received" => 7,
        "static_build_started" => 7,
        "static_building" => 7,
        "waiting_manual_fix" => 7,
        "github_commit_waiting" => 8,
        "cloudflare_deploying" => 9,
        "cloudflare_waiting" => 9,
        "cloudflare_failed" => 9,
        "cloudflare_verification_timeout" => 9,
        "public_url_verification_timeout" => 10,
        "cloudflare_published" => 11,
        "measurement_pending" => 11,
        "measurement_waiting" => 11,
        "ga4_pending" => 11,
        "gsc_pending" => 12,
        "learning_pending" => 13,
        "learning_waiting" => 13,
        "improvement_pending" => 14,
        "improvement_waiting" => 14,
        "completed" => 14
      }.freeze

      ERROR_STAGE_INDEX = {
        "handoff_failed" => 3,
        "repository_missing" => 4,
        "repository_mismatch" => 4,
        "branch_missing" => 4,
        "branch_mismatch" => 4,
        "webhook_enqueue_failed" => 5,
        "artifact_fetch_failed" => 6,
        "static_build_failed" => 7,
        "static_build_timeout" => 7,
        "static_build_package_json_missing" => 7,
        "static_build_package_json_invalid" => 7,
        "static_build_unsafe_lifecycle_script" => 7,
        "static_build_script_missing" => 7,
        "static_build_script_unsupported" => 7,
        "static_build_vite_missing" => 7,
        "static_build_framework_executable_missing" => 7,
        "static_build_package_manager_missing" => 7,
        "static_build_lockfile_generation_failed" => 7,
        "static_build_npm_ci_failed" => 7,
        "static_build_dependency_install_failed" => 7,
        "static_build_command_failed" => 7,
        "static_build_output_directory_missing" => 7,
        "static_build_output_ambiguous" => 7,
        "static_build_output_missing" => 7,
        "static_validation_failed" => 7,
        "github_permission_error" => 8,
        "result_import_failed" => 8,
        "cloudflare_failed" => 9,
        "cloudflare_verification_timeout" => 9,
        "public_url_verification_timeout" => 10,
        "ga4_failed" => 11,
        "gsc_failed" => 12,
        "learning_failed" => 13
      }.freeze
      AUTO_RECOVERABLE_ERROR_CODES = %w[
        webhook_enqueue_failed artifact_fetch_failed result_import_failed
      ].freeze

      def self.summary_for(landing_pages)
        pages = Array(landing_pages)
        failed_count = pages.count { |page| failed_page?(page) }
        published_count = pages.count(&:cloudflare_published?)
        {
          published_count:,
          processing_count: pages.count { |page| processing_page?(page) },
          failed_count:
        }
      end

      def self.failed_page?(page)
        metadata = page.metadata.to_h
        metadata["sync_status"] == "failed" ||
          metadata["cloudflare_deploy_status"].to_s.in?(%w[failed verification_timeout]) ||
          metadata.values_at("planning_status", "pipeline_stage").compact.any? { |value| value.to_s.include?("failed") }
      end
      private_class_method :failed_page?

      def self.processing_page?(page)
        return false if page.cloudflare_published? || failed_page?(page)

        metadata = page.metadata.to_h
        metadata["lovable_generation_run_id"].present? ||
          metadata.values_at("planning_status", "pipeline_stage", "sync_status").compact.any? do |value|
            value.to_s.in?(STATUS_STAGE_INDEX.keys - %w[completed improvement_pending improvement_waiting])
          end
      end
      private_class_method :processing_page?

      attr_reader :generation_run, :landing_page, :task, :business, :analytics_site,
        :learning_snapshot, :webhook_diagnostics, :cloudflare_configuration, :webhook_url

      def initialize(
        generation_run:,
        landing_page:,
        task:,
        business: nil,
        analytics_site: nil,
        learning_snapshot: nil,
        webhook_diagnostics: {},
        cloudflare_configuration: nil,
        webhook_url: nil
      )
        @generation_run = generation_run
        @landing_page = landing_page
        @task = task
        @business = business
        @analytics_site = analytics_site
        @learning_snapshot = learning_snapshot
        @webhook_diagnostics = webhook_diagnostics.to_h
        @cloudflare_configuration = cloudflare_configuration
        @webhook_url = webhook_url
      end

      def stages
        @stages ||= STAGE_DEFINITIONS.map.with_index(1) do |(key, label), number|
          Stage.new(
            number:,
            key:,
            label:,
            status: stage_status(number),
            timestamp: stage_timestamp(key),
            detail: stage_detail(key),
            diagnostics: stage_diagnostics(key)
          )
        end
      end

      def current_position
        completed? ? STAGE_DEFINITIONS.size : [ current_stage_index, STAGE_DEFINITIONS.size ].min
      end

      def current_stage
        stages.fetch(current_position - 1)
      end

      def current_label
        return "完了" if completed?

        current_stage.label
      end

      def stage_status_label(stage)
        return "完了" if stage.status == "completed"
        return "失敗" if stage.status == "failed"
        return "自動復旧中" if stage.status == "recovering"
        return "待機" if stage.status == "waiting"
        return "未開始" unless generation_run
        return "承認待ち" if stage.key == :approval
        return "Lovable待ち" if stage.key == :generate
        return "GitHub Push待ち" if stage.key == :github_source_push

        "実行中"
      end

      def next_label
        return "なし" if completed?

        stages[current_position]&.label || "完了"
      end

      def headline_status
        return "失敗" if failed?
        return "自動復旧中" if auto_recovering?
        return "完了" if completed?
        return "未開始" unless generation_run
        return "承認待ち" if approval_waiting?
        return "ユーザー操作待ち" if current_stage_index == 3

        "実行中"
      end

      def user_operation
        return failure_guidance if failed?
        return "なし" if auto_recovering?
        return "この画面で「＋LP作成」を選んでください" unless generation_run
        return "LP戦略とPromptを確認して承認してください" if approval_waiting?
        return "LovableでGenerateしてください" if current_stage_index == 3
        return "なし" if current_stage_index == 4
        return "なし" unless completed?

        "なし"
      end

      def next_action_text
        return failure_guidance if failed?
        return "一時エラーを検知しました。AICOOが自動で再試行しています。操作は不要です。" if auto_recovering?
        return "この画面で「＋LP作成」を開き、作成目的を指定してください。" unless generation_run
        return "LP戦略とPromptを確認して承認してください。" if approval_waiting?
        return "Lovableを開いてGenerateしてください。" if current_stage_index == 3
        return "GitHub Pushを待っています。Generate後は操作不要です。" if current_stage_index == 4
        return Aicoo::Lovable::StaticArtifactValidator::GA4_PUBLICATION_NOTICE if completed? && ga4_missing_warning?
        return "公開・計測・Learningが完了しました。AICOOが次の改善を判断します。" if completed?

        "現在AIが処理中です。操作は不要です。"
      end

      def failed?
        return false if auto_recovering?

        error_code.present? ||
          pipeline_status.to_s.include?("failed") ||
          pipeline_status == "waiting_manual_fix" ||
          (generation_run.respond_to?(:status) && generation_run.status == "failed") ||
          task&.status == "failed"
      end

      def auto_recovering?
        error_code.to_s.in?(AUTO_RECOVERABLE_ERROR_CODES) &&
          metadata.to_h["pipeline_recovery_status"] == "retrying"
      end

      def completed?
        current_stage_index > STAGE_DEFINITIONS.size && !failed?
      end

      def refresh?
        generation_run.present? && !completed? && !failed?
      end

      def approval_waiting?
        task&.status.to_s.in?(%w[draft waiting_approval]) || pipeline_status.to_s.in?(%w[prompt_pending prompt_ready lovable_pending waiting_approval])
      end

      def build_url
        metadata["build_url"].presence || task_metadata["lovable_build_url"].presence
      end

      def commit_sha
        metadata["github_commit_sha"].presence ||
          publication["commit_sha"].presence ||
          landing_page_metadata["github_commit_sha"].presence
      end

      def public_url
        metadata["cloudflare_url"].presence ||
          publication["production_url"].presence ||
          landing_page_metadata["cloudflare_url"].presence ||
          landing_page&.landing_page_url.presence
      end

      def error_message
        metadata["lovable_error_message"].presence ||
          generation_run&.error_message.presence ||
          task_metadata["lovable_error_message"].presence
      end

      def error_code
        metadata["lovable_error_code"].presence || task_metadata["lovable_error_code"].presence
      end

      def retryable?
        return false unless generation_run.present?

        error_code.to_s.in?(%w[artifact_fetch_failed result_import_failed]) ||
          (metadata["repository_import"] == true && error_code == "github_permission_error")
      end

      def settings_required?
        error_code.to_s.in?(%w[
          handoff_failed repository_missing repository_mismatch branch_missing branch_mismatch
          github_permission_error cloudflare_failed cloudflare_verification_timeout
          public_url_verification_timeout
        ])
      end

      def history
        @history ||= history_entries.sort_by(&:timestamp)
      end

      private

      def metadata
        @metadata ||= generation_run ? generation_run.metadata.to_h : {}
      end

      def landing_page_metadata
        @landing_page_metadata ||= landing_page ? landing_page.metadata.to_h : {}
      end

      def task_metadata
        @task_metadata ||= task ? task.metadata.to_h : {}
      end

      def publication
        @publication ||= metadata.to_h["publication"].to_h
      end

      def pipeline_status
        metadata.to_h["pipeline_status"].presence ||
          landing_page_metadata.to_h["planning_status"].presence ||
          landing_page_metadata.to_h["pipeline_stage"].presence ||
          task_metadata.to_h["pipeline_stage"].presence
      end

      def current_stage_index
        @current_stage_index ||= begin
          if failed? || auto_recovering?
            ERROR_STAGE_INDEX.fetch(error_code, STATUS_STAGE_INDEX.fetch(pipeline_status, 1))
          elsif approval_waiting?
            2
          elsif pipeline_status.to_s.in?(%w[improvement_pending improvement_waiting completed])
            completed_pipeline_stage_index
          else
            STATUS_STAGE_INDEX.fetch(pipeline_status, generation_run ? 2 : 1)
          end
        end
      end

      def completed_pipeline_stage_index
        return 14 if ga4_missing_warning?

        sources = metadata.to_h["measurement_sources"].to_h
        return 14 if sources.empty?
        return 11 unless sources["ga4"] == "available"
        return 12 unless sources["gsc"] == "available"

        14
      end

      def stage_status(number)
        return "failed" if failed? && number == current_stage_index
        return "recovering" if auto_recovering? && number == current_stage_index
        return "completed" if completed? || number < current_stage_index
        return "current" if number == current_stage_index

        "waiting"
      end

      def stage_timestamp(key)
        value = case key
        when :landing_page
          landing_page&.created_at || generation_run&.created_at
        when :approval
          task&.approved_at || metadata.to_h["lovable_prompt_approved_at"]
        when :generate
          metadata.to_h["github_webhook_received_at"]
        when :github_source_push, :webhook
          metadata.to_h["github_webhook_received_at"]
        when :artifact_fetch
          metadata.to_h["lovable_result_received_at"]
        when :static_build
          metadata.to_h["static_validation_completed_at"]
        when :publication_push
          publication["pushed_at"] || landing_page_metadata.to_h["last_push_at"]
        when :cloudflare, :http_verification
          publication["published_at"] || landing_page_metadata.to_h["last_published_at"]
        when :ga4
          measurement_timestamp("ga4")
        when :gsc
          measurement_timestamp("gsc")
        when :learning
          metadata.to_h["learning_completed_at"] || (metadata.to_h["measurement_checked_at"] if completed?)
        end
        parse_time(value)
      end

      def stage_detail(key)
        case key
        when :github_source_push, :webhook
          metadata.to_h["github_webhook_commit_sha"].presence
        when :publication_push
          commit_sha
        when :cloudflare, :http_verification
          public_url
        when :ga4
          measurement_source_label("ga4")
        when :gsc
          measurement_source_label("gsc")
        when :learning
          metadata.to_h["learning_status"].presence
        end
      end

      def stage_diagnostics(key)
        values = case key
        when :landing_page then landing_page_diagnostics
        when :approval then approval_diagnostics
        when :generate then generate_diagnostics
        when :github_source_push then github_source_push_diagnostics
        when :webhook then webhook_stage_diagnostics
        when :artifact_fetch then artifact_fetch_diagnostics
        when :static_build then static_build_diagnostics
        when :publication_push then publication_push_diagnostics
        when :cloudflare then cloudflare_diagnostics
        when :http_verification then http_verification_diagnostics
        when :ga4 then ga4_diagnostics
        when :gsc then gsc_diagnostics
        when :learning then learning_diagnostics
        else []
        end
        values + stage_error_diagnostics(key)
      end

      def landing_page_diagnostics
        [
          diagnostic("LP", landing_page_name),
          diagnostic("Business", safe_value(business, :name)),
          diagnostic("作成目的", landing_page_metadata["creation_purpose"] || landing_page_metadata["purpose"]),
          diagnostic("作成日時", landing_page&.created_at)
        ]
      end

      def approval_diagnostics
        [
          diagnostic("状態", task&.status || pipeline_status),
          diagnostic("承認日時", task&.approved_at || metadata["lovable_prompt_approved_at"]),
          diagnostic("Task", safe_value(task, :id)&.then { |id| "##{id}" }),
          diagnostic("実行前レビュー", task_metadata["pre_execution_review_status"])
        ]
      end

      def generate_diagnostics
        [
          diagnostic("Lovable Build URL", build_url, url: build_url),
          diagnostic("生成開始", metadata["lovable_started_at"] || metadata["build_url_generated_at"]),
          diagnostic("Version", metadata["version_label"] || metadata["version"]),
          diagnostic("状態", metadata["lovable_status"] || pipeline_status)
        ]
      end

      def github_source_push_diagnostics
        receipt = latest_webhook_receipt
        [
          diagnostic("Repository", source_repository, url: source_repository),
          diagnostic("Branch", source_branch),
          diagnostic("Commit SHA", metadata["github_webhook_commit_sha"] || receipt["commit_sha"]),
          diagnostic("Push日時", metadata["github_webhook_received_at"] || receipt["received_at"]),
          diagnostic("変更ファイル数", receipt["changed_file_count"]),
          diagnostic("変更ファイル一覧", receipt["changed_paths"]),
          diagnostic("Push時間", duration_ms(receipt["push_duration_ms"])),
          diagnostic("実行時間", duration_ms(receipt["processing_duration_ms"])),
          diagnostic("結果", metadata["github_webhook_status"] || stage_result(:github_source_push))
        ]
      end

      def webhook_stage_diagnostics
        receipt = latest_webhook_receipt
        [
          diagnostic("Webhook URL", webhook_url, url: webhook_url),
          diagnostic("受信日時", metadata["github_webhook_received_at"] || receipt["received_at"]),
          diagnostic("署名検証", receipt["signature_status"] || (receipt.present? ? "verified" : nil)),
          diagnostic("Repository", receipt["repository"] || source_repository, url: source_repository),
          diagnostic("Branch", receipt["branch"] || source_branch),
          diagnostic("Commit", receipt["commit_sha"] || metadata["github_webhook_commit_sha"]),
          diagnostic("Payload Size", bytes_label(receipt["payload_size_bytes"])),
          diagnostic("実行時間", duration_ms(receipt["processing_duration_ms"])),
          diagnostic("結果", metadata["github_webhook_status"] || webhook_diagnostics["last_status"]),
          diagnostic("失敗", stage_error_for(:webhook))
        ]
      end

      def artifact_fetch_diagnostics
        counts = metadata["artifact_file_counts"].to_h
        [
          diagnostic("Repository", source_repository, url: source_repository),
          diagnostic("取得ファイル数", metadata["artifact_fetched_file_count"]),
          diagnostic("HTML", counts["html"]),
          diagnostic("CSS", counts["css"]),
          diagnostic("JS", counts["javascript"]),
          diagnostic("画像", counts["images"]),
          diagnostic("除外ファイル", metadata["artifact_excluded_paths"]),
          diagnostic("Build対象", metadata["artifact_build_targets"]),
          diagnostic("処理時間", duration_ms(metadata["artifact_fetch_duration_ms"])),
          diagnostic("結果", stage_result(:artifact_fetch))
        ]
      end

      def static_build_diagnostics
        [
          diagnostic("Build開始", metadata["static_build_started_at"]),
          diagnostic("Build終了", metadata["static_build_command_finished_at"] ||
            metadata["static_validation_completed_at"]),
          diagnostic("処理時間", duration_ms(metadata["static_build_duration_ms"]) ||
            duration_between(metadata["static_build_started_at"], metadata["static_validation_completed_at"])),
          diagnostic("Framework", metadata["static_build_framework"]),
          diagnostic("Package manager", metadata["static_build_package_manager"]),
          diagnostic("実行コマンド", metadata["static_build_commands"]),
          diagnostic("Lockfile", metadata["static_build_lockfile_message"]),
          diagnostic("一時build設定", metadata["static_build_temporary_config_adjustments"]),
          diagnostic("終了コード", metadata["static_build_exit_code"]),
          diagnostic("stdout", metadata["static_build_stdout"]),
          diagnostic("stderr", metadata["static_build_stderr"]),
          diagnostic("検出候補", metadata["static_build_output_candidates"]),
          diagnostic("出力ディレクトリ", metadata["static_build_output_directory"]),
          diagnostic("build後ファイル", metadata["static_build_post_build_files"]),
          diagnostic("生成ファイル数", metadata["static_build_generated_file_count"]),
          diagnostic("Build Log", metadata["static_build_log"]),
          diagnostic("Service URL", metadata["service_url_auto_registration_notice"]),
          diagnostic("検出ファイル", metadata["static_validation_failure_file"]),
          diagnostic("検出行", metadata["static_validation_failure_line"]),
          diagnostic("検出URL", metadata["static_validation_failure_url"]),
          diagnostic("検出API", metadata["static_validation_failure_api"]),
          diagnostic("結果", metadata["static_build_status"] || stage_result(:static_build))
        ]
      end

      def publication_push_diagnostics
        [
          diagnostic("Repository", publication["repository_url"], url: publication["repository_url"]),
          diagnostic("Branch", publication["branch"]),
          diagnostic("Commit SHA", commit_sha),
          diagnostic("Push日時", publication["pushed_at"] || landing_page_metadata["last_push_at"]),
          diagnostic("変更ファイル数", publication["changed_file_count"]),
          diagnostic("変更ファイル一覧", publication["changed_paths"]),
          diagnostic("Push時間", duration_ms(publication["push_duration_ms"])),
          diagnostic("結果", publication["status"] || stage_result(:publication_push))
        ]
      end

      def cloudflare_diagnostics
        [
          diagnostic("Deploy開始", publication["pushed_at"] || landing_page_metadata["last_push_at"]),
          diagnostic("Deploy終了", publication["published_at"] || landing_page_metadata["last_published_at"]),
          diagnostic("Deploy時間", duration_between(
            publication["pushed_at"] || landing_page_metadata["last_push_at"],
            publication["published_at"] || landing_page_metadata["last_published_at"]
          )),
          diagnostic("公開URL", public_url, url: public_url),
          diagnostic("HTTP Status", publication["http_status"] || landing_page_metadata["cloudflare_http_status"]),
          diagnostic("Content-Type", publication["content_type"] || landing_page_metadata["cloudflare_content_type"]),
          diagnostic("Cloudflare Project", landing_page_metadata["cloudflare_project_name"] || cloudflare_project_name),
          diagnostic("自動再確認", recovery_attempt_label),
          diagnostic("結果", landing_page_metadata["cloudflare_deploy_status"] || stage_result(:cloudflare))
        ]
      end

      def http_verification_diagnostics
        [
          diagnostic("確認日時", landing_page_metadata["cloudflare_last_checked_at"] || publication["published_at"]),
          diagnostic("公開URL", public_url, url: public_url),
          diagnostic("HTTP Status", publication["http_status"] || landing_page_metadata["cloudflare_http_status"]),
          diagnostic("Content-Type", publication["content_type"] || landing_page_metadata["cloudflare_content_type"]),
          diagnostic("確認結果", landing_page_metadata["cloudflare_last_message"] ||
            landing_page_metadata["cloudflare_deploy_status"])
        ]
      end

      def ga4_diagnostics
        [
          diagnostic("設定元", business_common_setting_label),
          diagnostic("Property", analytics_site&.ga4_property_id),
          diagnostic("Measurement ID", ga4_measurement_id),
          diagnostic("Page Path", landing_page_ga4_path),
          diagnostic("警告", ga4_measurement_warning),
          diagnostic("初回計測", metadata["measurement_started_at"]),
          diagnostic("最新計測", analytics_site&.last_ga4_fetch_at || measurement_timestamp("ga4")),
          diagnostic("取得状態", measurement_source_label("ga4"))
        ]
      end

      def gsc_diagnostics
        [
          diagnostic("設定元", business_common_setting_label),
          diagnostic("Site", analytics_site&.gsc_site_url),
          diagnostic("対象URL", landing_page_metadata["gsc_url"] || public_url, url: landing_page_metadata["gsc_url"] || public_url),
          diagnostic("登録状態", analytics_site&.gsc_site_url.present? ? "Business共通設定済み" : nil),
          diagnostic("初回取得", metadata["measurement_started_at"]),
          diagnostic("最新取得", analytics_site&.last_gsc_fetch_at || measurement_timestamp("gsc")),
          diagnostic("取得状態", measurement_source_label("gsc"))
        ]
      end

      def learning_diagnostics
        learning = learning_payload
        [
          diagnostic("Snapshot", learning_snapshot && "##{learning_snapshot.id}"),
          diagnostic("Snapshot日時", learning_snapshot&.captured_at),
          diagnostic("改善候補数", learning_snapshot_payload.dig("evaluation", "improvement_candidate_count")),
          diagnostic("勝ちパターン", winning_pattern_label(learning)),
          diagnostic("Learning更新", metadata["learning_completed_at"] || learning["evaluated_at"]),
          diagnostic("処理時間", duration_ms(metadata["learning_duration_ms"])),
          diagnostic("状態", metadata["learning_status"] || learning["status"])
        ]
      end

      def stage_error_diagnostics(key)
        return [] unless stage_error_for(key).present?

        [ diagnostic("エラー", stage_error_for(key)) ]
      end

      def stage_error_for(key)
        return unless error_code.present?
        stage_number = STAGE_DEFINITIONS.index { |item| item.first == key }
        return unless stage_number && ERROR_STAGE_INDEX[error_code] == stage_number + 1

        error_message.presence || error_code
      end

      def stage_result(key)
        stage_number = STAGE_DEFINITIONS.index { |item| item.first == key }
        return unless stage_number

        case stage_status(stage_number + 1)
        when "completed" then "成功"
        when "failed" then "失敗"
        when "recovering" then "自動復旧中"
        when "current" then "実行中"
        else "待機"
        end
      end

      def diagnostic(label, value, url: nil)
        Diagnostic.new(label:, value: normalized_diagnostic_value(value), url:)
      end

      def normalized_diagnostic_value(value)
        return value if value.is_a?(Time) || value.is_a?(Date) || value.is_a?(ActiveSupport::TimeWithZone)
        return value.compact.map { |item| normalized_diagnostic_value(item) } if value.is_a?(Array)
        return value if value.is_a?(Hash)
        return value.dup.force_encoding(Encoding::UTF_8).scrub.presence if value.is_a?(String)

        value.presence
      end

      def latest_webhook_receipt
        @latest_webhook_receipt ||= Array(metadata["github_webhook_receipts"]).last.to_h
      end

      def source_repository
        metadata["lovable_result_repository"].presence ||
          safe_value(landing_page, :landing_page_repository_url)
      end

      def source_branch
        metadata["lovable_result_branch"].presence ||
          safe_value(landing_page, :landing_page_branch).presence ||
          "main"
      end

      def landing_page_name
        safe_value(landing_page, :landing_page_name).presence ||
          safe_value(landing_page, :name).presence ||
          landing_page_metadata["lp_name"]
      end

      def landing_page_ga4_path
        safe_value(landing_page, :landing_page_ga4_path).presence ||
          landing_page_metadata["ga4_page_path"]
      end

      def ga4_measurement_id
        business&.metadata.to_h&.dig("lp_ga4_measurement_id").presence ||
          landing_page_metadata["ga4_measurement_id"]
      end

      def business_common_setting_label
        return "Business共通設定" unless business

        business_name = business.name.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        "Business共通設定（#{business_name}）"
      end

      def cloudflare_project_name
        cloudflare_configuration&.project_name
      end

      def recovery_attempt_label
        attempt = landing_page_metadata["cloudflare_retry_count"] || metadata["cloudflare_retry_count"]
        return unless attempt

        "#{attempt} / #{Aicoo::CloudflarePagesDeploymentVerificationJob::MAX_ATTEMPTS}"
      end

      def learning_snapshot_payload
        @learning_snapshot_payload ||= learning_snapshot&.payload.to_h || {}
      end

      def learning_payload
        learning_snapshot_payload["learning"].to_h
      end

      def winning_pattern_label(learning)
        return unless learning.present?
        return "未確定" unless learning["status"] == "evaluated"

        type = learning["improvement_type"].presence || "改善"
        learning["success"] == true ? "#{type}（成功）" : "#{type}（未勝利）"
      end

      def safe_value(record, method)
        record.public_send(method) if record&.respond_to?(method)
      end

      def parse_time(value)
        return value.in_time_zone if value.respond_to?(:in_time_zone)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def duration_between(start_value, finish_value)
        started_at = parse_time(start_value)
        finished_at = parse_time(finish_value)
        return unless started_at && finished_at

        duration_seconds_label(finished_at - started_at)
      end

      def duration_ms(value)
        return if value.blank?

        duration_seconds_label(value.to_f / 1_000)
      end

      def duration_seconds_label(seconds)
        return if seconds.negative?
        return "#{(seconds * 1_000).round}ms" if seconds < 1

        "#{seconds.round(1)}秒"
      end

      def bytes_label(value)
        return if value.blank?

        number = value.to_i
        number >= 1_024 ? "#{(number.fdiv(1_024)).round(1)}KB" : "#{number}B"
      end

      def measurement_timestamp(source)
        return unless metadata.to_h.dig("measurement_sources", source) == "available"

        metadata.to_h["measurement_checked_at"]
      end

      def measurement_source_label(source)
        metadata.to_h.dig("measurement_sources", source).presence
      end

      def ga4_missing_warning?
        ga4_measurement_warning == Aicoo::Lovable::StaticArtifactValidator::GA4_MISSING_WARNING
      end

      def ga4_measurement_warning
        metadata["ga4_measurement_warning"].presence ||
          landing_page_metadata["ga4_measurement_warning"].presence ||
          Array(metadata["static_validation_warnings"]).find do |warning|
            warning == Aicoo::Lovable::StaticArtifactValidator::GA4_MISSING_WARNING
          end
      end

      def history_entries
        entries = stages.filter_map do |stage|
          next unless stage.timestamp

          HistoryEntry.new(timestamp: stage.timestamp, label: "#{stage.label}完了", detail: stage.detail)
        end
        launched_at = parse_time(metadata.to_h["build_url_generated_at"] || metadata.to_h["lovable_started_at"])
        if launched_at
          entries << HistoryEntry.new(timestamp: launched_at, label: "Lovable起動準備完了", detail: nil)
        end
        retry_at = parse_time(metadata["pipeline_last_retry_at"])
        if retry_at
          entries << HistoryEntry.new(
            timestamp: retry_at,
            label: "自動復旧を再試行",
            detail: "#{metadata['pipeline_retry_count']} / #{metadata['pipeline_retry_limit']}"
          )
        end
        page_path_generated_at = parse_time(metadata["page_path_generated_at"])
        if page_path_generated_at
          entries << HistoryEntry.new(
            timestamp: page_path_generated_at,
            label: metadata["page_path_generation_message"].presence || "page_pathを自動生成しました",
            detail: metadata["page_path"]
          )
        end
        lockfile_generated_at = parse_time(metadata["static_build_lockfile_generated_at"])
        if lockfile_generated_at
          entries << HistoryEntry.new(
            timestamp: lockfile_generated_at,
            label: metadata["static_build_lockfile_message"].presence ||
              "package-lock.jsonがなかったため一時生成しました",
            detail: metadata["static_build_package_manager"]
          )
        end
        cloudflare_public_url_acquired_at = parse_time(metadata["cloudflare_public_url_acquired_at"])
        if cloudflare_public_url_acquired_at
          entries << HistoryEntry.new(
            timestamp: cloudflare_public_url_acquired_at,
            label: metadata["cloudflare_public_url_acquired_message"].presence ||
              "Cloudflare公開URLを取得しました",
            detail: publication["production_url"]
          )
        end
        service_url_auto_registered_at = parse_time(metadata["service_url_auto_registered_at"])
        if service_url_auto_registered_at
          entries << HistoryEntry.new(
            timestamp: service_url_auto_registered_at,
            label: metadata["service_url_auto_registration_message"].presence ||
              "Service URLを自動登録しました",
            detail: publication["production_url"]
          )
        end
        ga4_warning_at = parse_time(metadata["ga4_measurement_warning_at"])
        if ga4_warning_at && ga4_measurement_warning.present?
          entries << HistoryEntry.new(
            timestamp: ga4_warning_at,
            label: ga4_measurement_warning,
            detail: nil
          )
        end
        entries
      end

      def failure_guidance
        if error_code.to_s.start_with?("static_build_")
          "Lovable成果物の#{error_message.presence || '静的build設定'}を修正してGitHubへPushしてください"
        else
          case error_code
          when "repository_missing", "repository_mismatch", "branch_missing", "branch_mismatch", "github_permission_error"
            "GitHub RepositoryとBranchの設定を確認してください"
          when "static_validation_failed"
            "Lovable成果物を修正してGitHubへPushしてください"
          when "cloudflare_failed", "cloudflare_verification_timeout", "public_url_verification_timeout"
            "Cloudflare設定と公開URLを確認してください"
          else
            "エラー内容を確認してください"
          end
        end
      end
    end
  end
end
