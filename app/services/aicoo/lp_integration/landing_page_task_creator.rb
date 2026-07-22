require "digest"
require "uri"

module Aicoo
  module LpIntegration
    class LandingPageTaskCreator
      Result = Data.define(:task, :created)

      def initialize(business:, landing_page:, generated_by: "owner")
        @business = business
        @landing_page = landing_page
        @generated_by = generated_by
      end

      def call
        validate!
        fingerprint = configuration_fingerprint
        existing = active_task_for(fingerprint)
        return Result.new(task: existing, created: false) if existing

        task = nil
        Business.transaction do
          candidate = create_candidate!
          task = create_task!(candidate, fingerprint)
          stamp_landing_page!(task)
        end
        Result.new(task:, created: true)
      end

      private

      attr_reader :business, :landing_page, :generated_by

      def validate!
        unless landing_page.business_id == business.id && landing_page.external_landing_page?
          raise ArgumentError, "このBusinessのLPではありません。"
        end
        raise ArgumentError, "LPのGitHubリポジトリを設定してください。" if repository_url.blank?
        raise ArgumentError, "BusinessのExecution Profileを設定してください。" unless business.business_execution_profile&.active?
      end

      def create_candidate!
        business.action_candidates.create!(
          title: "#{landing_page.landing_page_name}を同期・改善する",
          description: "LP専用リポジトリを同期し、Service本体を変更せず公開LPだけを更新します。",
          action_type: "ui_improvement",
          generation_source: "manual",
          department: "revenue",
          status: "proposal",
          success_probability: 0.7,
          expected_hours: 1,
          immediate_value_yen: 0,
          execution_prompt: execution_prompt,
          evaluation_reason: "Business詳細のLP一覧からOwnerが明示的に作成したLP専用同期タスクです。",
          metadata: candidate_metadata
        )
      end

      def create_task!(candidate, fingerprint)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: repository_name,
          target_repository_type: "static_site",
          title: candidate.title,
          execution_prompt: execution_prompt,
          priority_score: candidate.final_expected_value_yen.to_i,
          generated_by:,
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "external_lp_sync",
            "configuration_fingerprint" => fingerprint,
            "landing_page_prototype_id" => landing_page.id,
            "target_repository_url" => repository_url,
            "target_branch" => landing_page.landing_page_branch,
            "target_deploy_target" => "cloudflare_pages",
            "target_url" => landing_page.landing_page_url,
            "ga4_page_path" => landing_page.landing_page_ga4_path,
            "service_repository_protected" => true,
            "manual_approval_required" => true,
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "created_from" => "business_access_lp_list"
          }.compact
        )
      end

      def candidate_metadata
        {
          "workflow_type" => "external_lp_sync",
          "execution_mode" => "code_revision",
          "target_record_id" => landing_page.id,
          "target_url" => landing_page.landing_page_url,
          "target_metric" => "lp_conversion_rate",
          "change_content" => "LP専用リポジトリの内容だけを同期・改善する",
          "completion_criteria" => [
            "LP専用リポジトリだけが変更されている",
            "Service本体のリポジトリは変更されていない",
            "Cloudflare Pages向けの静的LPがPC・スマートフォンで表示できる",
            "GA4 page_pathとGSC URLが維持されている",
            "テスト・PR・公開確認結果が記録されている"
          ],
          "file_changes" => [ "LP repository root" ],
          "before" => "登録済みLPの同期または改善が未実施",
          "after" => "LP専用リポジトリへ変更を反映し、計測を維持した状態で公開確認済み",
          "landing_page_id" => landing_page.id,
          "lp_name" => landing_page.landing_page_name,
          "ga4_page_path" => landing_page.landing_page_ga4_path,
          "gsc_url" => landing_page.metadata.to_h["gsc_url"],
          "target_repository_url" => repository_url,
          "target_branch" => landing_page.landing_page_branch,
          "target_deploy_target" => "cloudflare_pages",
          "codex_eligible" => true,
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false,
          "owner_approval_required" => true,
          "service_repository_protected" => true
        }.compact
      end

      def execution_prompt
        <<~PROMPT
          #{landing_page.landing_page_name} のLP専用リポジトリだけを更新してください。

          - LP Repository: #{repository_url}
          - Branch: #{landing_page.landing_page_branch}
          - Public URL: #{landing_page.landing_page_url || "未公開"}
          - GA4 Page Path: #{landing_page.landing_page_ga4_path}
          - Hosting: Cloudflare Pages

          Service本体のリポジトリ、Render Service、DBには変更を加えないでください。
          LPのCTA・レスポンシブ表示・GA4/GSC計測を維持し、PRと公開確認結果を報告してください。
        PROMPT
      end

      def repository_url
        landing_page.landing_page_repository_url
      end

      def repository_name
        File.basename(URI.parse(repository_url).path, ".git")
      rescue URI::InvalidURIError
        repository_url.to_s.split("/").last
      end

      def configuration_fingerprint
        Digest::SHA256.hexdigest([
          landing_page.id,
          landing_page.updated_at.to_i,
          repository_url,
          landing_page.landing_page_branch,
          landing_page.landing_page_url,
          landing_page.landing_page_ga4_path
        ].join("|"))
      end

      def active_task_for(fingerprint)
        business.auto_revision_tasks.where(status: AutoRevisionTask::ACTIVE_STATUSES).find do |task|
          task.metadata.to_h["workflow_type"] == "external_lp_sync" &&
            task.metadata.to_h["configuration_fingerprint"] == fingerprint
        end
      end

      def stamp_landing_page!(task)
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "last_sync_requested_at" => Time.current.iso8601,
          "sync_status" => "task_created",
          "last_sync_task_id" => task.id,
          "last_error" => nil
        ))
      end
    end
  end
end
