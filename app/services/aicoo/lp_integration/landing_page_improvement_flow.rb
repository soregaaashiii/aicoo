require "uri"

module Aicoo
  module LpIntegration
    class LandingPageImprovementFlow
      Result = Data.define(:analysis, :task, :created)

      def initialize(business:, landing_page:, snapshots: nil)
        @business = business
        @landing_page = landing_page
        @snapshots = snapshots
      end

      def call
        validate!
        analysis = LandingPageImprovementAnalyzer.new(business:, landing_page:, snapshots:).call
        return Result.new(analysis:, task: nil, created: false) unless analysis.candidate

        existing = active_task_for(analysis.candidate)
        return Result.new(analysis:, task: existing, created: false) if existing

        task = create_task!(analysis.candidate)
        stamp_landing_page!(task)
        Result.new(analysis:, task:, created: true)
      end

      private

      attr_reader :business, :landing_page, :snapshots

      def validate!
        landing_page.reload if landing_page.persisted?
        raise ArgumentError, "公開中のLPだけが改善対象です。" unless landing_page.landing_page_public_status == "published"
        raise ArgumentError, "LPのGitHubリポジトリを設定してください。" if landing_page.landing_page_repository_url.blank?
      end

      def active_task_for(candidate)
        business.auto_revision_tasks.where(action_candidate: candidate, status: AutoRevisionTask::ACTIVE_STATUSES).first
      end

      def create_task!(candidate)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: repository_name,
          target_repository_type: "static_site",
          title: candidate.title,
          execution_prompt: candidate.execution_prompt,
          priority_score: candidate.final_expected_value_yen.to_i,
          generated_by: "owner",
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "external_lp_improvement",
            "landing_page_prototype_id" => landing_page.id,
            "campaign_id" => landing_page.business_campaign_id,
            "target_repository_url" => landing_page.landing_page_repository_url,
            "target_branch" => landing_page.landing_page_branch,
            "target_deploy_target" => "cloudflare_pages",
            "target_url" => landing_page.landing_page_url,
            "ga4_page_path" => landing_page.landing_page_ga4_path,
            "approval_required_reason" => "LP公開前にOwner確認が必要です。",
            "manual_approval_required" => true,
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "service_repository_protected" => true
          }.compact
        )
      end

      def stamp_landing_page!(task)
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "improvement_status" => "waiting_approval",
          "last_improvement_task_id" => task.id,
          "last_improvement_requested_at" => Time.current.iso8601
        ))
      end

      def repository_name
        File.basename(URI.parse(landing_page.landing_page_repository_url).path, ".git")
      rescue URI::InvalidURIError
        landing_page.landing_page_repository_url.to_s.split("/").last
      end
    end
  end
end
