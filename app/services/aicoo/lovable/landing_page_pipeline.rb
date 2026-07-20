require "json"
require "uri"

module Aicoo
  module Lovable
    class LandingPagePipeline
      Result = Data.define(:landing_page, :generation_run, :mode, :message)

      def initialize(client: McpClient.new, configuration: Configuration.new, launch_service: nil)
        @client = client
        @configuration = configuration
        @launch_service = launch_service || LaunchService.new(launcher: BuildWithUrlLauncher.new(configuration:))
      end

      def enqueue_create!(business:, action_candidate: nil)
        prepared = prepare_create!(business:, action_candidate:)
        launch!(business:, generation_run: prepared.generation_run)
      end

      def prepare_create!(business:, action_candidate: nil)
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
        Result.new(landing_page:, generation_run: run, mode: "prompt_review", message: "Lovable Promptを生成しました。")
      end

      def enqueue_revision!(business:, change_request:, action_candidate: nil)
        prepared = prepare_revision!(business:, change_request:, action_candidate:)
        launch!(business:, generation_run: prepared.generation_run)
      end

      def prepare_revision!(business:, change_request:, action_candidate: nil)
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
        Result.new(landing_page:, generation_run: run, mode: "prompt_review", message: "Lovable改善Promptを生成しました。")
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
        launch!(business:, generation_run: run)
      end

      def update_prompt!(business:, generation_run:, prompt:)
        validate_run_business!(generation_run, business)
        validate_prompt_editable!(generation_run)
        raise ArgumentError, "Lovable Promptが空です。" if prompt.blank?

        metadata = generation_run.metadata.to_h.deep_stringify_keys
        revision = metadata.fetch("prompt_revision", 1).to_i + 1
        generation_run.update!(
          prompt: prompt.to_s.first(BuildUrl::MAX_PROMPT_LENGTH),
          status: "draft",
          error_message: nil,
          metadata: metadata.merge(
            "pipeline_status" => "prompt_ready",
            "prompt_revision" => revision,
            "prompt_version" => prompt_version(metadata["version"], revision),
            "prompt_updated_at" => Time.current.iso8601,
            "build_url" => nil,
            "build_url_generated_at" => nil
          )
        )
        Result.new(
          landing_page: AicooLabLandingPage.find(metadata.fetch("landing_page_id")),
          generation_run:,
          mode: "prompt_review",
          message: "Lovable Promptを保存しました。"
        )
      end

      def regenerate_prompt!(business:, generation_run:)
        validate_run_business!(generation_run, business)
        validate_prompt_editable!(generation_run)
        metadata = generation_run.metadata.to_h.deep_stringify_keys
        landing_page = AicooLabLandingPage.find(metadata.fetch("landing_page_id"))
        repository = VersionRepository.new(business:, landing_page:)
        previous = AicooLabGenerationRun.find_by(id: metadata["previous_run_id"])
        refresh_learning!(business, repository.published)
        comparison = LandingPageLearningComparison.new(business:, repository:).call
        prompt = PromptBuilder.new(
          business:,
          landing_page:,
          previous_version: previous,
          learning_version: repository.published,
          best_version: comparison.best&.run,
          change_request: metadata["change_request"]
        ).call
        update_prompt!(business:, generation_run:, prompt:)
      end

      def launch!(business:, generation_run:)
        validate_run_business!(generation_run, business)
        metadata = generation_run.metadata.to_h.deep_stringify_keys
        launch = launch_service.call(prompt: generation_run.prompt, image_urls: reference_image_urls(business))
        launched_at = Time.current
        generation_run.update!(
          status: "succeeded",
          started_at: generation_run.started_at || launched_at,
          finished_at: launched_at,
          error_message: nil,
          metadata: metadata.merge(
            "pipeline_status" => "lovable_handoff_required",
            "connection_mode" => "build_url",
            "launcher" => launch.launcher_name,
            "build_url" => launch.url,
            "build_url_generated_at" => launched_at.iso8601,
            "launched_at" => launched_at.iso8601,
            "prompt_length" => launch.prompt_length,
            "reference_image_count" => launch.image_count,
            "handoff_reason" => "official_build_with_url"
          )
        )
        Result.new(
          landing_page: AicooLabLandingPage.find(metadata.fetch("landing_page_id")),
          generation_run:,
          mode: "build_url",
          message: "Lovable Build with URLを作成しました。"
        )
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
            "prompt_revision" => 1,
            "prompt_version" => prompt_version(repository.next_version, 1),
            "prompt_generated_at" => Time.current.iso8601,
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

      attr_reader :client, :configuration, :launch_service

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
            "pipeline_status" => "prompt_ready",
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
            "connection_mode" => "build_url",
            "launcher" => "build_with_url",
            "prompt_revision" => 1,
            "prompt_version" => prompt_version(version, 1),
            "prompt_generated_at" => Time.current.iso8601,
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

      def validate_prompt_editable!(run)
        metadata = run.metadata.to_h
        return if metadata["preview_url"].blank? && metadata.dig("publication", "published") != true

        raise ArgumentError, "Preview登録済みVersionのPromptは変更できません。新しいVersionを作成してください。"
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

      def prompt_version(version, revision)
        "v#{version}.p#{revision}"
      end

      def reference_image_urls(business)
        metadata = business.metadata.to_h.deep_stringify_keys
        values = Array(metadata["image_urls"]) + Array(metadata["images"]) + [ metadata["logo_url"], metadata["logo"] ]
        values.compact_blank.uniq.first(10)
      end
    end
  end
end
