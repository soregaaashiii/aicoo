module Aicoo
  module Lovable
    class ApprovedTaskStarter
      Result = Data.define(:task, :generation_run, :build_url, :idempotent)

      def initialize(task, pipeline: LandingPagePipeline.new, configuration: Configuration.new)
        @task = task
        @pipeline = pipeline
        @configuration = configuration
      end

      def call
        validate!
        run = AicooLabGenerationRun.find(task.metadata.to_h.fetch("lovable_generation_run_id"))
        existing_url = run.metadata.to_h["build_url"].presence
        if existing_url
          mark_approved!(run, existing_url)
          return Result.new(task:, generation_run: run, build_url: existing_url, idempotent: true)
        end
        if run.metadata.to_h["lovable_execution_mode"] == "lovable_mcp" &&
            run.metadata.to_h["lovable_mcp_task_id"].present?
          task.update!(status: "approved", approved_at: task.approved_at || Time.current)
          return Result.new(task:, generation_run: run, build_url: nil, idempotent: true)
        end

        task.update!(status: "approved", approved_at: task.approved_at || Time.current)
        return start_mcp!(run) if configuration.mcp_enabled?

        result = pipeline.launch!(business: task.business, generation_run: run)
        mark_approved!(result.generation_run, result.generation_run.metadata.to_h.fetch("build_url"))
        Result.new(
          task:,
          generation_run: result.generation_run,
          build_url: result.generation_run.metadata.to_h.fetch("build_url"),
          idempotent: false
        )
      rescue StandardError => e
        task.update!(
          status: "approved",
          approved_at: task.approved_at || Time.current,
          metadata: task.metadata.to_h.merge(
            "pipeline_stage" => "lovable_handoff_failed",
            "lovable_error_code" => "handoff_failed",
            "lovable_error_message" => e.message,
            "lovable_last_error_at" => Time.current.iso8601
          )
        ) if task.persisted?
        raise
      end

      private

      attr_reader :task, :pipeline, :configuration

      def validate!
        unless task.metadata.to_h["workflow_type"] == "external_lp_creation"
          raise ArgumentError, "Lovable LP作成Taskではありません。"
        end
        raise ArgumentError, "Lovable生成Runが未設定です。" if task.metadata.to_h["lovable_generation_run_id"].blank?
      end

      def mark_approved!(run, build_url)
        now = Time.current.iso8601
        execution_mode = run.metadata.to_h["lovable_execution_mode"].presence || "lovable_api"
        task.update!(
          status: "approved",
          approved_at: task.approved_at || Time.current,
          metadata: task.metadata.to_h.merge(
            "pipeline_stage" => "lovable_handoff_ready",
            "lovable_execution_mode" => execution_mode,
            "lovable_status" => "user_action_waiting",
            "lovable_build_url" => build_url,
            "lovable_started_at" => run.metadata.to_h["lovable_started_at"] || now,
            "lovable_error_code" => nil,
            "lovable_error_message" => nil
          )
        )
      end

      def start_mcp!(run)
        job = Aicoo::LovableLandingPageGenerationJob.perform_later(run.id)
        now = Time.current.iso8601
        run.update!(
          status: "running",
          started_at: run.started_at || Time.current,
          finished_at: nil,
          error_message: nil,
          metadata: run.metadata.to_h.merge(
            "pipeline_status" => "lovable_generation_started",
            "lovable_execution_mode" => "lovable_mcp",
            "lovable_status" => "generation_started",
            "lovable_started_at" => now,
            "lovable_mcp_task_id" => job.job_id,
            "lovable_mcp_request" => {
              "generation_run_id" => run.id,
              "prompt_version" => run.metadata.to_h["prompt_version"]
            }
          )
        )
        task.update!(
          status: "approved",
          approved_at: task.approved_at || Time.current,
          metadata: task.metadata.to_h.merge(
            "pipeline_stage" => "lovable_generation_started",
            "lovable_execution_mode" => "lovable_mcp",
            "lovable_status" => "generation_started",
            "lovable_mcp_task_id" => job.job_id
          )
        )
        Result.new(task:, generation_run: run, build_url: nil, idempotent: false)
      end
    end
  end
end
