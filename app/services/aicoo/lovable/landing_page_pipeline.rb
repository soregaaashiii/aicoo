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

      def prepare_external_create!(business:, landing_page_prototype:, strategy:, action_candidate: nil)
        unless landing_page_prototype.business_id == business.id && landing_page_prototype.external_landing_page?
          raise ArgumentError, "このBusinessのLPではありません。"
        end

        landing_page = ensure_landing_page_for_prototype!(business, landing_page_prototype, strategy)
        repository = VersionRepository.new(business:, landing_page:, landing_page_prototype:)
        prompt = PromptBuilder.new(business:, landing_page:, strategy:).call
        run = create_run!(
          business:,
          landing_page:,
          version: repository.next_version,
          request_type: "create",
          prompt:,
          action_candidate:,
          extra_metadata: {
            "landing_page_prototype_id" => landing_page_prototype.id,
            "campaign_id" => landing_page_prototype.business_campaign_id,
            "lp_strategy" => strategy
          }
        )
        Result.new(landing_page:, generation_run: run, mode: "prompt_review", message: "AICOOがLP戦略とLovable Promptを生成しました。")
      end

      def enqueue_revision!(business:, change_request:, action_candidate: nil)
        prepared = prepare_revision!(business:, change_request:, action_candidate:)
        launch!(business:, generation_run: prepared.generation_run)
      end

      def prepare_external_revision!(business:, landing_page_prototype:, change_request:, action_candidate: nil)
        raise ArgumentError, "修正内容を入力してください。" if change_request.blank?
        unless landing_page_prototype.business_id == business.id && landing_page_prototype.external_landing_page?
          raise ArgumentError, "このBusinessのLPではありません。"
        end

        landing_page = business.aicoo_lab_landing_pages.find_by(id: landing_page_prototype.metadata.to_h["lovable_landing_page_id"])
        raise ArgumentError, "修正元のLovable LPがありません。" unless landing_page

        repository = VersionRepository.new(business:, landing_page:, landing_page_prototype:)
        previous = repository.current || raise(ArgumentError, "修正元のLovable Versionがありません。")
        strategy = landing_page_prototype.metadata.to_h["lp_strategy"].to_h
        prompt = PromptBuilder.new(
          business:,
          landing_page:,
          previous_version: previous,
          learning_version: repository.published,
          change_request:,
          strategy:
        ).call
        run = create_run!(
          business:,
          landing_page:,
          version: repository.next_version,
          request_type: "revision",
          prompt:,
          previous_run: previous,
          change_request:,
          action_candidate:,
          extra_metadata: {
            "landing_page_prototype_id" => landing_page_prototype.id,
            "campaign_id" => landing_page_prototype.business_campaign_id,
            "lp_strategy" => strategy
          }
        )
        Result.new(landing_page:, generation_run: run, mode: "prompt_review", message: "Lovable改善Promptを生成しました。")
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
          retry_of: generation_run,
          extra_metadata: generation_run.metadata.to_h.slice("landing_page_prototype_id", "campaign_id", "lp_strategy")
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
        prototype = BusinessPrototype.find_by(id: metadata["landing_page_prototype_id"])
        repository = VersionRepository.new(business:, landing_page:, landing_page_prototype: prototype)
        previous = AicooLabGenerationRun.find_by(id: metadata["previous_run_id"])
        refresh_learning!(business, repository.published)
        comparison = LandingPageLearningComparison.new(business:, repository:).call
        prompt = PromptBuilder.new(
          business:,
          landing_page:,
          previous_version: previous,
          learning_version: repository.published,
          best_version: comparison.best&.run,
          change_request: metadata["change_request"],
          strategy: metadata["lp_strategy"]
        ).call
        update_prompt!(business:, generation_run:, prompt:)
      end

      def launch!(business:, generation_run:)
        validate_run_business!(generation_run, business)
        metadata = generation_run.metadata.to_h.deep_stringify_keys
        ensure_external_run_approved!(business, metadata)
        if metadata["build_url"].present?
          return Result.new(
            landing_page: AicooLabLandingPage.find(metadata.fetch("landing_page_id")),
            generation_run:,
            mode: metadata["lovable_execution_mode"].presence || "lovable_api",
            message: "既存のLovable Build with URLを利用します。"
          )
        end

        launch = launch_service.call(prompt: generation_run.prompt, image_urls: reference_image_urls(business))
        launched_at = Time.current
        generation_run.update!(
          status: "succeeded",
          started_at: generation_run.started_at || launched_at,
          finished_at: launched_at,
          error_message: nil,
          metadata: metadata.merge(
            "pipeline_status" => "lovable_handoff_ready",
            "connection_mode" => "lovable_api",
            "lovable_execution_mode" => "lovable_api",
            "lovable_status" => "user_action_waiting",
            "launcher" => launch.launcher_name,
            "build_url" => launch.url,
            "lovable_execution_url" => launch.url,
            "build_url_generated_at" => launched_at.iso8601,
            "launched_at" => launched_at.iso8601,
            "lovable_started_at" => launched_at.iso8601,
            "prompt_length" => launch.prompt_length,
            "reference_image_count" => launch.image_count,
            "handoff_reason" => "official_build_with_url"
          )
        )
        stamp_external_handoff!(business, generation_run)
        Result.new(
          landing_page: AicooLabLandingPage.find(metadata.fetch("landing_page_id")),
          generation_run:,
          mode: "lovable_api",
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
        stamp_external_preview!(business, metadata, preview_url)
        Result.new(landing_page:, generation_run:, mode: "registered", message: "Lovable Previewを登録しました。")
      end

      def register_result!(
        business:,
        generation_run:,
        project_url: nil,
        project_id: nil,
        result_repository: nil,
        result_branch: nil,
        preview_url: nil
      )
        validate_run_business!(generation_run, business)
        validate_optional_http_url!(project_url, "Lovable project URL")
        validate_optional_http_url!(result_repository, "生成結果Repository")
        validate_optional_http_url!(preview_url, "Preview URL")
        validate_github_repository_url!(result_repository)
        raise ArgumentError, "Lovable project URLまたは生成結果Repositoryを入力してください。" if project_url.blank? && result_repository.blank?

        metadata = generation_run.metadata.to_h.deep_stringify_keys
        now = Time.current
        project_identifier = project_id.presence || lovable_project_id(project_url)
        next_status = result_repository.present? ? "github_webhook_waiting" : "lovable_generation_waiting"
        generation_run.update!(
          status: "succeeded",
          generated_count: preview_url.present? ? 1 : generation_run.generated_count,
          metadata: metadata.merge(
            "pipeline_status" => next_status,
            "lovable_status" => result_repository.present? ? "webhook_waiting" : "generation_waiting",
            "lovable_project_url" => project_url.presence || metadata["lovable_project_url"],
            "lovable_project_id" => project_identifier.presence || metadata["lovable_project_id"],
            "project_id" => project_identifier.presence || metadata["project_id"],
            "preview_url" => preview_url.presence || metadata["preview_url"],
            "lovable_result_repository" => result_repository.presence || metadata["lovable_result_repository"],
            "lovable_result_branch" => result_branch.presence || metadata["lovable_result_branch"] || "main",
            "lovable_completed_at" => result_repository.present? ? now.iso8601 : metadata["lovable_completed_at"],
            "lovable_result_registered_at" => now.iso8601,
            "lovable_error_code" => nil,
            "lovable_error_message" => nil
          ).compact
        )
        stamp_external_result!(business, generation_run)
        Result.new(
          landing_page: AicooLabLandingPage.find(metadata.fetch("landing_page_id")),
          generation_run:,
          mode: generation_run.metadata.to_h["lovable_execution_mode"].presence || configuration.connection_mode,
          message: result_repository.present? ? "Lovable生成結果Repositoryを登録しました。GitHub Pushを待ちます。" : "Lovable project URLを登録しました。"
        )
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

      def create_run!(business:, landing_page:, version:, request_type:, prompt:, action_candidate: nil, previous_run: nil, change_request: nil, retry_of: nil, extra_metadata: {})
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
            "connection_mode" => configuration.connection_mode,
            "lovable_execution_mode" => configuration.connection_mode,
            "lovable_status" => "waiting_approval",
            "launcher" => "build_with_url",
            "prompt_revision" => 1,
            "prompt_version" => prompt_version(version, 1),
            "prompt_generated_at" => Time.current.iso8601,
            "publication" => {},
            "created_by" => "owner"
          }.compact.merge(extra_metadata.to_h.deep_stringify_keys)
        )
      end

      def ensure_landing_page_for_prototype!(business, prototype, strategy)
        existing_id = prototype.metadata.to_h["lovable_landing_page_id"]
        existing = business.aicoo_lab_landing_pages.find_by(id: existing_id)
        return existing if existing

        experiment = AicooLabExperiment.create!(
          title: "#{prototype.landing_page_name} Lovable生成",
          description: strategy["reason"],
          experiment_type: "lp",
          acquisition_channel: acquisition_channel_for(prototype.business_campaign&.campaign_type),
          status: "draft",
          approval_status: "pending",
          expected_90d_profit_yen: strategy["expected_profit_yen"].to_i,
          success_probability: strategy["confidence"].to_d,
          budget_yen: 0,
          estimated_work_minutes: (strategy["estimated_work_hours"].to_d * 60).round,
          notes: "External LP prototype ##{prototype.id}",
          created_by: "aicoo_lp_strategy"
        )
        landing_page = experiment.create_aicoo_lab_landing_page!(
          business:,
          headline: strategy["headline"],
          subheadline: strategy["subheadline"],
          body: Array(strategy["structure"]).join("\n"),
          cta_text: strategy["cta"],
          seo_title: strategy["seo_title"],
          seo_description: strategy["meta_description"],
          status: "draft",
          public_status: "draft",
          generation_source: "lovable",
          notes: "AICOO LP strategy for BusinessPrototype ##{prototype.id}"
        )
        prototype.update!(metadata: prototype.metadata.to_h.merge("lovable_landing_page_id" => landing_page.id))
        landing_page
      end

      def acquisition_channel_for(campaign_type)
        {
          "seo" => "seo",
          "google_ads" => "ads",
          "meta_ads" => "ads",
          "sns" => "sns",
          "email" => "direct",
          "referral" => "referral"
        }.fetch(campaign_type.to_s, "direct")
      end

      def stamp_external_handoff!(business, generation_run)
        metadata = generation_run.metadata.to_h
        prototype = business.business_prototypes.find_by(id: metadata["landing_page_prototype_id"])
        return unless prototype

        task = business.auto_revision_tasks.find_by(id: metadata["auto_revision_task_id"])
        task&.update!(metadata: task.metadata.to_h.merge(
          "pipeline_stage" => "lovable_handoff_ready",
          "lovable_prompt_approved_at" => Time.current.iso8601,
          "build_url_generated_at" => metadata["build_url_generated_at"],
          "lovable_build_url" => metadata["build_url"],
          "lovable_execution_mode" => metadata["lovable_execution_mode"],
          "lovable_status" => metadata["lovable_status"]
        ))
        prototype.update!(metadata: prototype.metadata.to_h.merge(
          "planning_status" => "lovable_handoff_ready",
          "lovable_build_url" => metadata["build_url"],
          "lovable_build_url_generated_at" => metadata["build_url_generated_at"],
          "lovable_execution_mode" => metadata["lovable_execution_mode"],
          "lovable_status" => metadata["lovable_status"]
        ))
      end

      def stamp_external_result!(business, generation_run)
        metadata = generation_run.metadata.to_h
        prototype = business.business_prototypes.find_by(id: metadata["landing_page_prototype_id"])
        return unless prototype

        prototype.update!(metadata: prototype.metadata.to_h.merge(
          "planning_status" => metadata["pipeline_status"],
          "lovable_project_url" => metadata["lovable_project_url"],
          "lovable_project_id" => metadata["lovable_project_id"],
          "lovable_result_repository" => metadata["lovable_result_repository"],
          "lovable_result_branch" => metadata["lovable_result_branch"],
          "lovable_status" => metadata["lovable_status"],
          "lovable_last_sync_at" => metadata["lovable_result_registered_at"]
        ).compact)
      end

      def ensure_external_run_approved!(business, metadata)
        return if metadata["landing_page_prototype_id"].blank?

        task = business.auto_revision_tasks.find_by(id: metadata["auto_revision_task_id"])
        unless task&.approved_at.present? && !task.status.in?(%w[draft waiting_approval])
          raise ArgumentError, "Lovableへ渡す前にAutoRevisionTaskを承認してください。"
        end
      end

      def validate_optional_http_url!(value, label)
        return if value.blank? || valid_http_url?(value)

        raise ArgumentError, "#{label}はhttps://またはhttp://で入力してください。"
      end

      def lovable_project_id(value)
        return if value.blank?

        uri = URI.parse(value)
        uri.path.to_s.split("/").reject(&:blank?).last
      rescue URI::InvalidURIError
        nil
      end

      def validate_github_repository_url!(value)
        return if value.blank?

        uri = URI.parse(value)
        return if uri.host.to_s.casecmp("github.com").zero? && uri.path.to_s.split("/").reject(&:blank?).size >= 2

        raise ArgumentError, "生成結果RepositoryはGitHub Repository URLを入力してください。"
      rescue URI::InvalidURIError
        raise ArgumentError, "生成結果RepositoryはGitHub Repository URLを入力してください。"
      end

      def stamp_external_preview!(business, metadata, preview_url)
        prototype = business.business_prototypes.find_by(id: metadata["landing_page_prototype_id"])
        return unless prototype

        prototype.update!(metadata: prototype.metadata.to_h.merge(
          "planning_status" => "preview_ready",
          "cloudflare_preview_url" => preview_url,
          "preview_registered_at" => Time.current.iso8601
        ))
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
