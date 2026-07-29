module Aicoo
  module Lovable
    class PipelineOverview
      Stage = Data.define(:number, :key, :label, :status, :timestamp, :detail)
      HistoryEntry = Data.define(:timestamp, :label, :detail)

      STAGE_DEFINITIONS = [
        [ :landing_page, "LP作成" ],
        [ :approval, "承認" ],
        [ :generate, "Generate" ],
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

      attr_reader :generation_run, :landing_page, :task

      def initialize(generation_run:, landing_page:, task:)
        @generation_run = generation_run
        @landing_page = landing_page
        @task = task
      end

      def stages
        @stages ||= STAGE_DEFINITIONS.map.with_index(1) do |(key, label), number|
          Stage.new(
            number:,
            key:,
            label:,
            status: stage_status(number),
            timestamp: stage_timestamp(key),
            detail: stage_detail(key)
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
        return "待機" if stage.status == "waiting"
        return "承認待ち" if stage.key == :approval
        return "Generate待ち" if stage.key == :generate
        return "GitHub Push待ち" if stage.key == :github_source_push

        "実行中"
      end

      def next_label
        return "なし" if completed?

        stages[current_position]&.label || "完了"
      end

      def headline_status
        return "失敗" if failed?
        return "完了" if completed?
        return "未開始" unless generation_run
        return "承認待ち" if approval_waiting?
        return "ユーザー操作待ち" if current_stage_index.in?([ 3, 4 ])

        "実行中"
      end

      def user_operation
        return failure_guidance if failed?
        return "BusinessのLP一覧から「＋LP追加」を選んでください" unless generation_run
        return "LP戦略とPromptを確認して承認してください" if approval_waiting?
        return "LovableでGenerateしてください" if current_stage_index == 3
        return "LovableでGenerate後、GitHubへPushしてください" if current_stage_index == 4
        return "なし" unless completed?

        "なし"
      end

      def next_action_text
        return failure_guidance if failed?
        return "BusinessのLP一覧から「＋LP追加」を選び、作成目的を指定してください。" unless generation_run
        return "LP戦略とPromptを確認して承認してください。" if approval_waiting?
        return "Lovableを開いてGenerateしてください。" if current_stage_index == 3
        return "LovableでGenerateしてください。GitHub Push後はAICOOが自動で進めます。" if current_stage_index == 4
        return "公開・計測・Learningが完了しました。AICOOが次の改善を判断します。" if completed?

        "現在AIが処理中です。操作は不要です。"
      end

      def failed?
        error_code.present? ||
          pipeline_status.to_s.include?("failed") ||
          pipeline_status == "waiting_manual_fix" ||
          (generation_run.respond_to?(:status) && generation_run.status == "failed") ||
          task&.status == "failed"
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
        error_code.to_s.in?(%w[artifact_fetch_failed result_import_failed]) &&
          generation_run.present?
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
          if failed?
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
        sources = metadata.to_h["measurement_sources"].to_h
        return 14 if sources.empty?
        return 11 unless sources["ga4"] == "available"
        return 12 unless sources["gsc"] == "available"

        14
      end

      def stage_status(number)
        return "failed" if failed? && number == current_stage_index
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

      def measurement_timestamp(source)
        return unless metadata.to_h.dig("measurement_sources", source) == "available"

        metadata.to_h["measurement_checked_at"]
      end

      def measurement_source_label(source)
        metadata.to_h.dig("measurement_sources", source).presence
      end

      def parse_time(value)
        return value.in_time_zone if value.respond_to?(:in_time_zone)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
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
        entries
      end

      def failure_guidance
        case error_code
        when "repository_missing", "repository_mismatch", "branch_missing", "branch_mismatch", "github_permission_error"
          "GitHub RepositoryとBranchの設定を確認してください"
        when "static_build_failed", "static_validation_failed"
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
