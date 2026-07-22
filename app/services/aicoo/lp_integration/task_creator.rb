require "digest"

module Aicoo
  module LpIntegration
    class TaskCreator
      Result = Data.define(:task, :created)

      def initialize(business:, generated_by: "owner")
        @business = business
        @generated_by = generated_by
      end

      def call
        validate_configuration!
        fingerprint = configuration_fingerprint
        existing = active_task_for(fingerprint)
        return Result.new(task: existing, created: false) if existing

        task = nil
        Business.transaction do
          candidate = create_candidate!
          task = create_task!(candidate, fingerprint)
          stamp_source!(task)
        end
        Result.new(task:, created: true)
      end

      private

      attr_reader :business, :generated_by

      def overview
        @overview ||= Overview.new(business)
      end

      def prompt
        @prompt ||= PromptBuilder.new(overview).call
      end

      def validate_configuration!
        raise ArgumentError, "実装先リポジトリを設定してください。" if overview.app_repository_url.blank?
        raise ArgumentError, "LP作成元を設定してください。" unless overview.source_reference_present?
      end

      def create_candidate!
        business.action_candidates.create!(
          title: "#{business.name}の外部LPを独立事業リポジトリへ取り込む",
          description: "登録済みのLP作成元を独立事業へ移植し、GA4・GSC・Activity APIの計測を整備します。",
          action_type: "build_lp",
          generation_source: "manual",
          department: "revenue",
          status: "proposal",
          success_probability: 0.5,
          expected_hours: 4,
          expected_profit_yen: 0,
          expected_revenue_value_yen: 0,
          expected_learning_value_yen: 0,
          expected_total_value_yen: 0,
          final_expected_value_yen: 0,
          execution_prompt: prompt,
          evaluation_reason: "OwnerがLP・計測連携画面から明示的に作成した外部リポジトリ向けタスクです。",
          metadata: candidate_metadata
        )
      end

      def create_task!(candidate, fingerprint)
        AutoRevisionTask.create!(
          action_candidate: candidate,
          business:,
          target_business: business,
          target_repository_name: overview.execution_profile&.repository_name.presence || business.name,
          target_repository_type: overview.app_framework,
          title: candidate.title,
          execution_prompt: prompt,
          priority_score: 0,
          generated_by:,
          risk_level: "medium",
          status: "waiting_approval",
          metadata: {
            "workflow_type" => "external_lp_import",
            "configuration_fingerprint" => fingerprint,
            "lp_source_prototype_id" => overview.source_prototype&.id,
            "target_repository_url" => overview.app_repository_url,
            "target_branch" => overview.app_branch,
            "manual_approval_required" => true,
            "approval_required_reason" => "外部事業リポジトリへのLP取り込みはOwner確認後に実行します。",
            "auto_submit_enabled" => false,
            "auto_merge_enabled" => false,
            "auto_deploy_enabled" => false,
            "contains_lp_source_code" => false,
            "created_from" => "business_lp_integration"
          }
        )
      end

      def candidate_metadata
        root_path = overview.marketing_root_path.presence || "既存構造を調査して決定"
        {
          "workflow_type" => "external_lp_import",
          "execution_mode" => "code_revision",
          "target_record_id" => business.id,
          "target_metric" => "lp_conversion",
          "change_content" => "外部LPを独立事業の公開領域へ移植し、問い合わせ・GA4・Activity APIを接続する",
          "completion_criteria" => [
            "独立事業リポジトリだけが変更されている",
            "LPと問い合わせフォームがPC・スマートフォンで動作する",
            "GA4標準イベントが設定されている",
            "AICOO停止時も問い合わせ保存が成功する",
            "テスト・PR・デプロイ・本番確認結果が記録されている"
          ],
          "file_changes" => [ root_path ],
          "before" => "LP作成元はAICOOに設定済みだが、独立事業への移植・計測確認は未実施",
          "after" => "独立事業側へLPを実装し、問い合わせ・GA4・GSC・Activity APIを確認済み",
          "source_repository_url" => overview.lp_source_repository_url,
          "source_branch" => overview.lp_source_branch,
          "source_url" => overview.lp_source_url,
          "target_repository_url" => overview.app_repository_url,
          "target_branch" => overview.app_branch,
          "marketing_root_path" => overview.marketing_root_path,
          "codex_eligible" => true,
          "auto_revision" => false,
          "auto_merge" => false,
          "auto_deploy" => false,
          "owner_approval_required" => true,
          "manual_task_creation_only" => true,
          "contains_lp_source_code" => false
        }.compact
      end

      def configuration_fingerprint
        Digest::SHA256.hexdigest([
          overview.lp_source_type,
          overview.lp_source_repository_url,
          overview.lp_source_branch,
          overview.lp_source_url,
          overview.app_repository_url,
          overview.app_branch,
          overview.marketing_root_path,
          overview.ga4_measurement_id,
          overview.gsc_site_url
        ].join("|"))
      end

      def active_task_for(fingerprint)
        business.auto_revision_tasks.where(status: AutoRevisionTask::ACTIVE_STATUSES).find do |task|
          task.metadata.to_h["workflow_type"] == "external_lp_import" &&
            task.metadata.to_h["configuration_fingerprint"] == fingerprint
        end
      end

      def stamp_source!(task)
        prototype = overview.source_prototype
        return unless prototype

        prototype.update!(metadata: prototype.metadata.to_h.merge(
          "last_task_created_at" => Time.current.iso8601,
          "last_sync_task_id" => task.id,
          "last_error" => nil
        ))
      end
    end
  end
end
