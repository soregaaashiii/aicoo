module Aicoo
  module Lovable
    class PipelineDiagnosisSnapshot
      METADATA_KEY = "pipeline_diagnosis_snapshot".freeze
      COMPONENT_KEYS = %i[lovable github webhook cloudflare ga4 gsc learning].freeze
      LEVEL_PRIORITY = {
        "error" => 0,
        "settings" => 1,
        "warning" => 2,
        "healthy" => 3
      }.freeze
      COMPONENT_LABELS = {
        lovable: "Lovable",
        github: "GitHub",
        webhook: "Webhook",
        cloudflare: "Cloudflare",
        ga4: "GA4",
        gsc: "GSC",
        learning: "Learning"
      }.freeze
      COMPONENT_SETTINGS = {
        lovable: [ "Lovable Project URL", "LP詳細 → 設定 → Lovable Project URL" ],
        github: [ "GitHub Repository / Branch / Token", "LP詳細 → 設定 → GitHub Repository" ],
        webhook: [ "Payload URL / application/json / Secret / Push event", "GitHub Repository → Settings → Webhooks → Add webhook" ],
        cloudflare: [ "Cloudflare Account ID / API Token / Project", "AICOO → Lovable接続 → Cloudflare Pages公開設定" ],
        ga4: [ "Google認証 / GA4 Property ID", "Business → Google設定" ],
        gsc: [ "Google認証 / GSC Site URL", "Business → Google設定" ],
        learning: [ nil, nil ]
      }.freeze

      class << self
        def read(generation_run)
          payload = generation_run&.metadata.to_h[METADATA_KEY].to_h
          return if payload.blank?

          components = Array(payload["components"]).filter_map { |row| load_component(row.to_h) }
          return if components.empty?

          next_action = payload["next_action"].to_h
          PipelineDiagnosis::Result.new(
            level: payload["level"].presence || overall_level(components),
            status_label: payload["status_label"].presence ||
              PipelineDiagnosis::LEVEL_LABELS.fetch(overall_level(components)),
            components:,
            next_action: PipelineDiagnosis::NextAction.new(
              text: next_action["text"].presence || "操作不要です。現在AICOOが処理中です。",
              kind: (next_action["kind"].presence || "none").to_sym,
              component: next_action["component"]&.to_sym
            )
          )
        end

        def write!(generation_run:, result:, source:)
          now = Time.current
          snapshot = dump(result, checked_at: now, source:)
          generation_run.with_lock do
            metadata = generation_run.reload.metadata.to_h.merge(METADATA_KEY => snapshot)
            generation_run.update_columns(metadata:, updated_at: now)
          end
          result
        end

        def summary_for(landing_pages:, generation_runs_by_id:)
          pages = Array(landing_pages)
          return PipelineDiagnosis::Summary.new(label: "LP未登録", level: "warning") if pages.empty?

          runs = pages.filter_map do |page|
            generation_runs_by_id[page.metadata.to_h["lovable_generation_run_id"].to_i]
          end
          summaries = runs.filter_map { |run| saved_summary(run) }
          return summaries.min_by { |summary| LEVEL_PRIORITY.fetch(summary.level, 9) } if summaries.any?

          legacy_summary(runs)
        end

        def unavailable_result(generation_run)
          metadata = generation_run&.metadata.to_h || {}
          components = COMPONENT_KEYS.map do |key|
            component_from_saved_state(key, metadata)
          end
          level = overall_level(components)
          PipelineDiagnosis::Result.new(
            level:,
            status_label: PipelineDiagnosis::LEVEL_LABELS.fetch(level),
            components:,
            next_action: unavailable_next_action(metadata)
          )
        end

        private

        def dump(result, checked_at:, source:)
          {
            "version" => 1,
            "checked_at" => checked_at.iso8601,
            "source" => source.to_s,
            "level" => result.level,
            "status_label" => result.status_label,
            "components" => result.components.map { |component| dump_component(component) },
            "next_action" => {
              "text" => result.next_action.text,
              "kind" => result.next_action.kind.to_s,
              "component" => result.next_action.component&.to_s
            },
            "summary" => dump_summary(summary_from_result(result))
          }
        end

        def dump_component(component)
          {
            "key" => component.key.to_s,
            "label" => component.label,
            "level" => component.level,
            "status_label" => component.status_label,
            "connection_status" => component.connection_status,
            "cause" => component.cause,
            "required_setting" => component.required_setting,
            "settings_location" => component.settings_location,
            "fix_steps" => component.fix_steps,
            "recheckable" => component.recheckable,
            "details" => component.details
          }
        end

        def load_component(row)
          key = row["key"].to_s.to_sym
          return unless key.in?(COMPONENT_KEYS)

          PipelineDiagnosis::Component.new(
            key:,
            label: row["label"],
            level: row["level"],
            status_label: row["status_label"],
            connection_status: row["connection_status"],
            cause: row["cause"],
            required_setting: row["required_setting"],
            settings_location: row["settings_location"],
            fix_steps: Array(row["fix_steps"]),
            recheckable: row["recheckable"] == true,
            details: row["details"].to_h
          )
        end

        def saved_summary(run)
          row = run.metadata.to_h.dig(METADATA_KEY, "summary").to_h
          return if row.blank?

          PipelineDiagnosis::Summary.new(label: row["label"], level: row["level"])
        end

        def dump_summary(summary)
          { "label" => summary.label, "level" => summary.level }
        end

        def summary_from_result(result)
          actionable = result.components.select(&:actionable?)
          if actionable.any? { |component| component.key == :github }
            return PipelineDiagnosis::Summary.new(label: "GitHub設定不足", level: actionable.find { |row| row.key == :github }.level)
          end
          if actionable.any? { |component| component.key == :cloudflare }
            return PipelineDiagnosis::Summary.new(label: "Cloudflare設定不足", level: actionable.find { |row| row.key == :cloudflare }.level)
          end
          google = actionable.find { |component| component.key.in?(%i[ga4 gsc]) }
          if google
            label = google.cause.to_s.include?("再認証") ? "Google再認証必要" : "#{google.label}設定不足"
            return PipelineDiagnosis::Summary.new(label:, level: google.level)
          end
          unless result.component(:learning)&.healthy?
            return PipelineDiagnosis::Summary.new(label: "Learning待ち", level: "warning")
          end

          PipelineDiagnosis::Summary.new(label: "すべて正常", level: "healthy")
        end

        def legacy_summary(runs)
          return PipelineDiagnosis::Summary.new(label: "Pipeline未開始", level: "warning") if runs.empty?

          error_codes = runs.filter_map { |run| run.metadata.to_h["lovable_error_code"].presence }
          if error_codes.any? { |code| code.in?(PipelineDiagnosis::GITHUB_ERROR_CODES) }
            return PipelineDiagnosis::Summary.new(label: "GitHub設定不足", level: "error")
          end
          if error_codes.any? { |code| code.in?(PipelineDiagnosis::CLOUDFLARE_ERROR_CODES) }
            return PipelineDiagnosis::Summary.new(label: "Cloudflare設定不足", level: "error")
          end
          learning_ready = runs.any? do |run|
            metadata = run.metadata.to_h
            metadata["learning_completed_at"].present? ||
              metadata["pipeline_status"].to_s.in?(%w[improvement_pending improvement_waiting completed])
          end
          return PipelineDiagnosis::Summary.new(label: "Learning待ち", level: "warning") unless learning_ready

          PipelineDiagnosis::Summary.new(label: "すべて正常", level: "healthy")
        end

        def component_from_saved_state(key, metadata)
          partial = metadata.dig("pipeline_diagnosis", key.to_s).to_h
          level = partial["level"].presence || inferred_level(key, metadata)
          PipelineDiagnosis::Component.new(
            key:,
            label: COMPONENT_LABELS.fetch(key),
            level:,
            status_label: PipelineDiagnosis::LEVEL_LABELS.fetch(level),
            connection_status: level.in?(%w[healthy warning]) ? "OK" : "NG",
            cause: partial["cause"].presence || "保存済み診断結果の更新を待っています。",
            required_setting: partial["required_setting"].presence || COMPONENT_SETTINGS.fetch(key).first,
            settings_location: partial["settings_location"].presence || COMPONENT_SETTINGS.fetch(key).last,
            fix_steps: Array(partial["fix_steps"]).presence || default_fix_steps(key),
            recheckable: partial["recheckable"] == true,
            details: partial["details"].to_h
          )
        end

        def inferred_level(key, metadata)
          error_code = metadata["lovable_error_code"].to_s
          return "error" if key == :github && error_code.in?(PipelineDiagnosis::GITHUB_ERROR_CODES)
          return "error" if key == :cloudflare && error_code.in?(PipelineDiagnosis::CLOUDFLARE_ERROR_CODES)
          return "healthy" if key == :learning && metadata["learning_completed_at"].present?

          "warning"
        end

        def unavailable_next_action(metadata)
          if metadata.empty?
            return PipelineDiagnosis::NextAction.new(
              text: "このLPの作成目的を選んで生成を開始してください。",
              kind: :create,
              component: nil
            )
          end
          if metadata["pipeline_status"].to_s == "waiting_approval"
            return PipelineDiagnosis::NextAction.new(
              text: "LP戦略とPromptを確認して承認してください。",
              kind: :approve,
              component: nil
            )
          end

          PipelineDiagnosis::NextAction.new(
            text: "保存済み診断結果を更新中です。現在のPipeline処理はそのまま継続します。",
            kind: :none,
            component: nil
          )
        end

        def overall_level(components)
          return "error" if components.any? { |component| component.level == "error" }
          return "settings" if components.any? { |component| component.level == "settings" }
          return "warning" if components.any? { |component| component.level == "warning" }

          "healthy"
        end

        def default_fix_steps(key)
          case key
          when :github then [ "RepositoryとBranchを確認する", "再確認を押す" ]
          when :webhook then [ "GitHubのWebhook設定を確認する", "再確認を押す" ]
          when :cloudflare then [ "Cloudflare設定を確認する", "再確認を押す" ]
          when :ga4, :gsc then [ "Business共通Google設定を確認する" ]
          when :lovable then [ "Lovable Project URLを確認する" ]
          else []
          end
        end
      end
    end
  end
end
