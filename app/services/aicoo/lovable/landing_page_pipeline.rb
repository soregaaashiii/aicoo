require "json"
require "uri"

module Aicoo
  module Lovable
    class LandingPagePipeline
      Result = Data.define(:landing_page, :generation_run, :mode, :message)

      def initialize(client: McpClient.new, configuration: Configuration.new)
        @client = client
        @configuration = configuration
      end

      def enqueue_create!(business:, action_candidate: nil)
        landing_page = ensure_landing_page!(business)
        repository = VersionRepository.new(business:, landing_page:)
        refresh_learning!(business, repository.published)
        comparison = LandingPageLearningComparison.new(business:, repository:).call
        prompt = PromptBuilder.new(
          business:,
          landing_page:,
          previous_version: repository.current,
          learning_version: repository.published,
          best_version: comparison.best&.run
        ).call
        run = create_run!(
          business:,
          landing_page:,
          version: repository.next_version,
          request_type: "create",
          prompt:,
          action_candidate:
        )
        dispatch!(run)
      end

      def enqueue_revision!(business:, change_request:, action_candidate: nil)
        raise ArgumentError, "修正内容を入力してください。" if change_request.blank?

        landing_page = lovable_landing_page!(business)
        repository = VersionRepository.new(business:, landing_page:)
        previous = repository.current || raise(ArgumentError, "修正元のLovable Versionがありません。")
        refresh_learning!(business, repository.published)
        comparison = LandingPageLearningComparison.new(business:, repository:).call
        prompt = PromptBuilder.new(
          business:,
          landing_page:,
          previous_version: previous,
          learning_version: repository.published,
          best_version: comparison.best&.run,
          change_request:
        ).call
        run = create_run!(
          business:,
          landing_page:,
          version: repository.next_version,
          request_type: "revision",
          prompt:,
          previous_run: previous,
          change_request:,
          action_candidate:
        )
        dispatch!(run)
      end

      def enqueue_retry!(business:, generation_run:)
        validate_run_business!(generation_run, business)
        raise ArgumentError, "失敗したVersionだけ再送できます。" unless generation_run.status == "failed"

        landing_page = AicooLabLandingPage.find(generation_run.metadata.to_h.fetch("landing_page_id"))
        run = create_run!(
          business:,
          landing_page:,
          version: generation_run.metadata.to_h["version"].to_i,
          request_type: "retry",
          prompt: generation_run.prompt,
          previous_run: generation_run,
          change_request: generation_run.metadata.to_h["change_request"],
          retry_of: generation_run
        )
        dispatch!(run)
      end

      def execute!(run)
        metadata = run.metadata.to_h.deep_stringify_keys
        business = Business.find(metadata.fetch("business_id"))
        landing_page = AicooLabLandingPage.find(metadata.fetch("landing_page_id"))
        run.update!(status: "running", started_at: run.started_at || Time.current, error_message: nil)

        project_payload, message_payload, diff_payload = execute_remote!(run, metadata, business)
        project = project_details(project_payload, message_payload)
        completed_metadata = metadata.merge(
          "pipeline_status" => "preview_ready",
          "project_id" => project["project_id"],
          "preview_url" => project["preview_url"],
          "editor_url" => project["editor_url"],
          "sandbox_url" => project["sandbox_url"],
          "latest_commit_sha" => project["latest_commit_sha"],
          "message_id" => project["message_id"],
          "diff" => compact_payload(diff_payload),
          "lovable_response" => compact_payload(message_payload.presence || project_payload),
          "completed_at" => Time.current.iso8601
        ).compact

        unless valid_http_url?(completed_metadata["preview_url"])
          raise McpClient::Error, "LovableからPreview URLが返りませんでした。Projectは保持されています。"
        end

        run.update!(
          status: "succeeded",
          response: JSON.pretty_generate(compact_payload(project_payload.merge("message" => message_payload))),
          metadata: completed_metadata,
          generated_count: 1,
          finished_at: Time.current
        )
        mark_preview_ready!(landing_page, run)
        Result.new(landing_page:, generation_run: run, mode: "mcp", message: "Lovable Preview v#{metadata['version']}を生成しました。")
      rescue StandardError => e
        fail_run!(run, e)
        raise
      end

      def register_preview!(business:, generation_run:, preview_url:, editor_url: nil, project_id: nil)
        validate_run_business!(generation_run, business)
        raise ArgumentError, "Preview URLはhttps://またはhttp://で入力してください。" unless valid_http_url?(preview_url)

        metadata = generation_run.metadata.to_h.merge(
          "pipeline_status" => "preview_ready",
          "preview_url" => preview_url,
          "editor_url" => editor_url.presence || generation_run.metadata.to_h["editor_url"],
          "project_id" => project_id.presence || generation_run.metadata.to_h["project_id"],
          "preview_registered_at" => Time.current.iso8601,
          "preview_registered_by" => "owner"
        ).compact
        generation_run.update!(status: "succeeded", metadata:, generated_count: 1, finished_at: Time.current)
        landing_page = AicooLabLandingPage.find(metadata.fetch("landing_page_id"))
        mark_preview_ready!(landing_page, generation_run)
        Result.new(landing_page:, generation_run:, mode: "registered", message: "Lovable Previewを登録しました。")
      end

      def restore!(business:, generation_run:)
        validate_run_business!(generation_run, business)
        raise ArgumentError, "成功Versionだけを復元できます。" unless generation_run.status == "succeeded"

        landing_page = AicooLabLandingPage.find(generation_run.metadata.to_h.fetch("landing_page_id"))
        repository = VersionRepository.new(business:, landing_page:)
        restored = create_run!(
          business:,
          landing_page:,
          version: repository.next_version,
          request_type: "restore",
          prompt: generation_run.prompt,
          previous_run: repository.current,
          change_request: "v#{generation_run.metadata.to_h['version']}へ戻す"
        )
        restored.update!(
          status: "succeeded",
          response: generation_run.response,
          generated_count: 1,
          finished_at: Time.current,
          metadata: generation_run.metadata.to_h.merge(
            "business_id" => business.id,
            "landing_page_id" => landing_page.id,
            "pipeline" => "lovable",
            "pipeline_status" => "preview_ready",
            "version" => repository.next_version,
            "version_label" => "v#{repository.next_version}",
            "request_type" => "restore",
            "restored_from_run_id" => generation_run.id,
            "previous_run_id" => repository.current&.id,
            "restored_at" => Time.current.iso8601,
            "publication" => {}
          )
        )
        mark_preview_ready!(landing_page, restored)
        Result.new(landing_page:, generation_run: restored, mode: "restore", message: "v#{generation_run.metadata.to_h['version']}を新しいCurrent Versionとして復元しました。")
      end

      private

      attr_reader :client, :configuration

      def dispatch!(run)
        if client.configured?
          Aicoo::LovableLandingPageGenerationJob.perform_later(run.id)
          Result.new(
            landing_page: AicooLabLandingPage.find(run.metadata.to_h["landing_page_id"]),
            generation_run: run,
            mode: "mcp",
            message: "Lovableへ生成依頼を送信しました。"
          )
        else
          build_url = BuildUrl.call(run.prompt, base_url: configuration.build_url)
          run.update!(
            status: "succeeded",
            finished_at: Time.current,
            metadata: run.metadata.to_h.merge(
              "pipeline_status" => "lovable_handoff_required",
              "connection_mode" => "build_url",
              "build_url" => build_url,
              "handoff_reason" => "lovable_mcp_oauth_not_configured"
            )
          )
          Result.new(
            landing_page: AicooLabLandingPage.find(run.metadata.to_h["landing_page_id"]),
            generation_run: run,
            mode: "build_url",
            message: "Lovable Build URLを作成しました。生成後にPreview URLを登録してください。"
          )
        end
      end

      def execute_remote!(run, metadata, business)
        project_id = inherited_project_id(metadata)
        if metadata["request_type"].in?(%w[revision retry]) && project_id.present?
          message_payload = client.send_message(project_id:, message: run.prompt)
          refreshed = client.get_project(project_id:)
          message_id = find_value(message_payload, %w[message_id id])
          diff = client.get_diff(project_id:, message_id:)
          return [ refreshed, message_payload, diff ]
        end

        created = client.create_project(
          description: "#{business.name} LP v#{metadata['version']}",
          initial_message: run.prompt
        )
        created_project_id = find_value(created, %w[project_id id])
        refreshed = created_project_id.present? ? client.get_project(project_id: created_project_id) : created
        [ created.merge("refreshed_project" => refreshed), {}, {} ]
      end

      def create_run!(business:, landing_page:, version:, request_type:, prompt:, action_candidate: nil, previous_run: nil, change_request: nil, retry_of: nil)
        AicooLabGenerationRun.create!(
          generation_type: "lp_generation",
          status: "draft",
          prompt:,
          generated_count: 0,
          started_at: Time.current,
          metadata: {
            "pipeline" => "lovable",
            "pipeline_status" => "queued",
            "business_id" => business.id,
            "business_name" => business.name,
            "landing_page_id" => landing_page.id,
            "experiment_id" => landing_page.aicoo_lab_experiment_id,
            "action_candidate_id" => action_candidate&.id || previous_run&.metadata.to_h&.dig("action_candidate_id"),
            "version" => version,
            "version_label" => "v#{version}",
            "request_type" => request_type,
            "change_request" => change_request,
            "previous_run_id" => previous_run&.id,
            "retry_of_run_id" => retry_of&.id,
            "connection_mode" => configuration.connection_mode,
            "publication" => {},
            "created_by" => "owner"
          }.compact
        )
      end

      def ensure_landing_page!(business)
        existing = lovable_landing_page(business)
        return existing if existing

        experiment = AicooLabExperiment.create!(
          title: "#{business.name} LP",
          description: business.description,
          experiment_type: "lp",
          acquisition_channel: "direct",
          status: "draft",
          approval_status: "pending",
          expected_90d_profit_yen: 0,
          success_probability: 0,
          budget_yen: 0,
          estimated_work_minutes: 0,
          notes: "Lovable generation for Business ##{business.id}",
          created_by: "lovable"
        )
        experiment.create_aicoo_lab_landing_page!(
          business:,
          headline: business.name,
          subheadline: business.description,
          body: business.description,
          cta_text: business.metadata.to_h["cta"].presence || "問い合わせる",
          status: "draft",
          public_status: "draft",
          generation_source: "lovable",
          notes: "Lovableで生成中"
        )
      end

      def lovable_landing_page(business)
        runs = VersionRepository.new(business:).all
        landing_page_id = runs.first&.metadata.to_h&.dig("landing_page_id")
        return AicooLabLandingPage.find_by(id: landing_page_id) if landing_page_id.present?

        business.aicoo_lab_landing_pages.where(generation_source: "lovable").order(updated_at: :desc).first
      end

      def lovable_landing_page!(business)
        lovable_landing_page(business) || raise(ArgumentError, "Lovable LPがまだありません。先にLP作成を実行してください。")
      end

      def mark_preview_ready!(landing_page, run)
        landing_page.update!(
          status: "preview_ready",
          generated_at: Time.current,
          notes: "Lovable #{run.metadata.to_h['version_label']} / project #{run.metadata.to_h['project_id']}"
        )
        experiment = landing_page.aicoo_lab_experiment
        experiment.update!(
          status: "preview_ready",
          approval_status: "pending",
          preview_url: run.metadata.to_h["preview_url"]
        )
      end

      def fail_run!(run, error)
        run.update!(
          status: "failed",
          error_message: error.message,
          finished_at: Time.current,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "failed",
            "failed_at" => Time.current.iso8601,
            "failure_class" => error.class.name,
            "failure_reason" => error.message
          )
        )
      rescue StandardError => persistence_error
        Rails.logger.error("[Lovable] failed to persist generation error run_id=#{run.id}: #{persistence_error.message}")
      end

      def validate_run_business!(run, business)
        return if run.metadata.to_h["pipeline"] == "lovable" && run.metadata.to_h["business_id"].to_i == business.id

        raise ActiveRecord::RecordNotFound, "Lovable Versionが見つかりません。"
      end

      def inherited_project_id(metadata)
        return metadata["project_id"] if metadata["project_id"].present?

        previous = AicooLabGenerationRun.find_by(id: metadata["previous_run_id"] || metadata["retry_of_run_id"])
        previous&.metadata.to_h&.dig("project_id")
      end

      def project_details(*payloads)
        payload = payloads.compact.reduce({}) { |memo, item| memo.deep_merge(item.to_h.deep_stringify_keys) }
        {
          "project_id" => find_value(payload, %w[project_id]),
          "preview_url" => find_value(payload, %w[preview_url]),
          "editor_url" => find_value(payload, %w[editor_url project_url]),
          "sandbox_url" => find_value(payload, %w[sandbox_url]),
          "latest_commit_sha" => find_value(payload, %w[latest_commit_sha commit_sha]),
          "message_id" => find_value(payload, %w[message_id])
        }.compact
      end

      def find_value(value, keys)
        case value
        when Hash
          keys.each { |key| return value[key] if value[key].present? }
          value.each_value do |child|
            found = find_value(child, keys)
            return found if found.present?
          end
        when Array
          value.each do |child|
            found = find_value(child, keys)
            return found if found.present?
          end
        end
        nil
      end

      def compact_payload(value)
        JSON.parse(JSON.generate(value))
      rescue JSON::GeneratorError
        { "text" => value.to_s }
      end

      def valid_http_url?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def refresh_learning!(business, published_version)
        return unless published_version

        LearningSummary.new(business:, generation_run: published_version).call(persist: true)
      end
    end
  end
end
