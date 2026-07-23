require "uri"

module Aicoo
  module LpIntegration
    class LandingPageImprovementFlow
      Result = Data.define(:analysis, :task, :created)

      def initialize(business:, landing_page:, snapshots: nil, analysis: nil)
        @business = business
        @landing_page = landing_page
        @snapshots = snapshots
        @analysis = analysis
      end

      def call
        validate!
        analysis = @analysis || LandingPageImprovementAnalyzer.new(business:, landing_page:, snapshots:).call
        return Result.new(analysis:, task: nil, created: false) unless analysis.candidate

        existing = active_task_for(analysis.candidate)
        return Result.new(analysis:, task: existing, created: false) if existing

        task = nil
        Business.transaction do
          variant = create_variant!
          task = create_task!(analysis.candidate, variant)
          stamp_landing_pages!(task, variant)
        end
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

      def create_task!(candidate, variant)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: repository_name,
          target_repository_type: "static_site",
          title: "#{landing_page.landing_page_name}のB Variantを作成する",
          execution_prompt: ab_execution_prompt(candidate, variant),
          priority_score: candidate.final_expected_value_yen.to_i,
          generated_by: "owner",
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "external_lp_improvement",
            "landing_page_prototype_id" => variant.id,
            "source_landing_page_prototype_id" => landing_page.id,
            "campaign_id" => landing_page.business_campaign_id,
            "target_repository_url" => landing_page.landing_page_repository_url,
            "target_branch" => landing_page.landing_page_branch,
            "target_deploy_target" => "cloudflare_pages",
            "target_url" => variant.landing_page_url,
            "ga4_page_path" => variant.landing_page_ga4_path,
            "ab_test_mode" => "create_variant",
            "ab_variant" => "B",
            "preserve_source_landing_page" => true,
            "approval_required_reason" => "LP公開前にOwner確認が必要です。",
            "manual_approval_required" => true,
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "service_repository_protected" => true
          }.compact
        )
      end

      def create_variant!
        base_name = landing_page.landing_page_name.sub(/\s+[A-Z]\z/, "")
        sequence = landing_page.business_campaign.landing_pages.active.where("name LIKE ?", "#{base_name} B%").count + 1
        variant_name = sequence == 1 ? "#{base_name} B" : "#{base_name} B#{sequence}"
        variant_path = "#{landing_page.landing_page_ga4_path.to_s.sub(%r{/\z}, '')}-b#{sequence}"
        variant = LandingPageRegistry.new(business:).save!(
          campaign_id: landing_page.business_campaign_id,
          name: variant_name,
          source_type: landing_page.landing_page_source_type,
          repository_url: landing_page.landing_page_repository_url,
          branch: landing_page.landing_page_branch,
          lovable_project_url: landing_page.metadata.to_h["lovable_project_url"],
          public_status: "testing",
          ga4_page_path: variant_path,
          cta: landing_page.metadata.to_h["cta"],
          improvement_target: landing_page.metadata.to_h["improvement_target"],
          ab_test_name: "#{base_name} improvement",
          ab_variant: "B",
          ab_status: "running"
        )
        variant.update!(metadata: variant.metadata.to_h.merge(
          "ab_source_landing_page_id" => landing_page.id,
          "planning_status" => "waiting_approval",
          "service_repository_protected" => true
        ))
        variant
      end

      def stamp_landing_pages!(task, variant)
        landing_page.update!(metadata: landing_page.metadata.to_h.merge(
          "improvement_status" => "waiting_approval",
          "last_improvement_task_id" => task.id,
          "last_improvement_requested_at" => Time.current.iso8601,
          "active_ab_variant_id" => variant.id,
          "ab_test" => landing_page.landing_page_ab_test.merge("variant" => "A", "status" => "running")
        ))
        variant.update!(metadata: variant.metadata.to_h.merge("last_improvement_task_id" => task.id))
      end

      def ab_execution_prompt(candidate, variant)
        <<~PROMPT
          #{candidate.execution_prompt}

          A/Bテストとして新しいLP Variant Bを作成してください。
          - 現行LP A（BusinessPrototype ##{landing_page.id}）は上書きしない
          - 新規LP B（BusinessPrototype ##{variant.id}）として実装する
          - Bのpage_path: #{variant.landing_page_ga4_path}
          - Service本体のリポジトリや処理は変更しない
          - Cloudflare Pagesへの公開はOwner承認後に行う
        PROMPT
      end

      def repository_name
        File.basename(URI.parse(landing_page.landing_page_repository_url).path, ".git")
      rescue URI::InvalidURIError
        landing_page.landing_page_repository_url.to_s.split("/").last
      end
    end
  end
end
