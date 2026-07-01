module Aicoo
  class NewLpAutoDeployPolicy
    Result = Data.define(:allowed, :reasons, :business, :auto_revision_task) do
      def allowed?
        allowed
      end

      def message
        allowed? ? "新規LP/Lab Businessの低リスク自動deploy対象です。" : reasons.join(" / ")
      end
    end

    def initialize(subject)
      @subject = subject
    end

    def call
      Result.new(
        allowed: reasons.empty?,
        reasons:,
        business:,
        auto_revision_task:
      )
    end

    def allowed?
      call.allowed?
    end

    def record_history!(event:, success:, auto_build_task: nil, metadata: {})
      task = auto_revision_task || auto_build_task&.auto_revision_task
      related_business = business || task&.business || auto_build_task&.business
      return unless related_business

      occurred_at = Time.current
      payload = {
        "event" => event,
        "success" => success,
        "auto_build_task_id" => auto_build_task&.id,
        "auto_revision_task_id" => task&.id,
        "risk_level" => task&.risk_level,
        "occurred_at" => occurred_at.iso8601,
        "metadata" => metadata
      }
      append_metadata_history!(auto_build_task, payload) if auto_build_task
      append_metadata_history!(task, payload) if task
      record_activity!(related_business, payload)
    end

    def suspend!(reason:, auto_build_task: nil, metadata: {})
      related_business = business || auto_build_task&.business
      return unless related_business

      related_business.suspend_auto_deploy!(reason:)
      record_history!(
        event: "auto_deploy_suspended",
        success: false,
        auto_build_task:,
        metadata: metadata.merge("reason" => reason)
      )
    end

    private

    attr_reader :subject

    def auto_revision_task
      return @auto_revision_task if defined?(@auto_revision_task)

      @auto_revision_task =
        case subject
        when AutoRevisionTask
          subject
        when AutoBuildTask
          subject.auto_revision_task
        end
    end

    def business
      return @business if defined?(@business)

      @business =
        case subject
        when Business
          subject
        when AutoBuildTask
          subject.business
        when AutoRevisionTask
          subject.business
        end
    end

    def reasons
      @reasons ||= build_reasons
    end

    def build_reasons
      items = []
      items << "business_missing" unless business
      return items if business.blank?

      items << "new_lp_auto_deploy_disabled" unless business.new_lp_auto_deploy_enabled?
      items << "auto_deploy_suspended" if business.auto_deploy_suspended?
      items << "not_new_lp_lifecycle" unless Business::NEW_LP_AUTO_DEPLOY_LIFECYCLE_STAGES.include?(business.lifecycle_stage)
      items << "production_or_archived_business" if business.production_like_business?
      items << "revenue_business" if business.revenue_recorded?
      items << "excluded_business" if Business::NEW_LP_AUTO_DEPLOY_EXCLUDED_NAMES.include?(business.name) || business.system_business?
      items << "risk_not_low" if auto_revision_task && auto_revision_task.risk_level != "low"
      items
    end

    def append_metadata_history!(record, payload)
      metadata = record.metadata.to_h
      history = Array(metadata["auto_deploy_history"]).last(20)
      record.update!(metadata: metadata.merge("auto_deploy_history" => history + [ payload ]))
    end

    def record_activity!(related_business, payload)
      BusinessActivityLog.record!(
        business: related_business,
        attributes: {
          source_app: "aicoo",
          source_method: "logger",
          activity_type: "new_lp_auto_deploy_#{payload.fetch('event')}",
          resource_type: auto_revision_task ? "AutoRevisionTask" : "Business",
          resource_id: (auto_revision_task&.id || related_business.id).to_s,
          title: activity_title(payload),
          occurred_at: payload.fetch("occurred_at"),
          detected_at: Time.current,
          diff_summary: payload.fetch("metadata", {})["reason"],
          metadata: payload,
          idempotency_key: idempotency_key(related_business, payload)
        }
      )
    end

    def activity_title(payload)
      case payload.fetch("event")
      when "auto_deploy_ready" then "新規LPの自動デプロイ候補になりました"
      when "deploy_succeeded" then "新規LPを自動デプロイしました"
      when "deploy_failed" then "新規LPの自動デプロイに失敗しました"
      when "auto_deploy_suspended" then "新規LPの自動デプロイを停止しました"
      else "新規LP自動デプロイ履歴"
      end
    end

    def idempotency_key(related_business, payload)
      [
        "new_lp_auto_deploy",
        related_business.id,
        payload.fetch("event"),
        payload["auto_build_task_id"],
        payload["auto_revision_task_id"],
        Time.zone.parse(payload.fetch("occurred_at")).to_i
      ].join(":")
    end
  end
end
