require "uri"

module Aicoo
  class ArticleOpportunityCodexGate
    MODEL_NAME = ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME
    ALLOWED_TYPES = %w[ctr_improvement rank_improvement internal_link_addition content_update].freeze
    BLOCKED_TYPES = %w[shop_addition verified_shop_addition].freeze
    ACTIVE_TASK_STATUSES = AutoRevisionTask::ACTIVE_STATUSES.freeze
    SAFE_HOSTS = %w[suelog.jp www.suelog.jp].freeze

    Result = Data.define(
      :candidate,
      :eligible,
      :reasons,
      :risk_level,
      :executor,
      :execution_mode,
      :profile,
      :existing_task,
      :latest_snapshot,
      :metadata
    ) do
      def eligible?
        eligible
      end
    end

    def self.call(action_candidate, require_approval: true, ignore_existing_task: false)
      new(action_candidate, require_approval:, ignore_existing_task:).call
    end

    def self.article_opportunity_candidate?(action_candidate)
      metadata = action_candidate&.metadata.to_h
      metadata["value_model_name"].to_s == MODEL_NAME &&
        metadata["analysis_source"].to_s == "article_analytics_snapshot"
    end

    def initialize(action_candidate, require_approval: true, ignore_existing_task: false)
      @candidate = action_candidate
      @require_approval = require_approval
      @ignore_existing_task = ignore_existing_task
      @metadata = action_candidate.metadata.to_h.deep_stringify_keys
      @brief = metadata["execution_brief"].to_h
      @reasons = []
    end

    def call
      evaluate
      Result.new(
        candidate:,
        eligible: reasons.empty?,
        reasons: reasons.uniq,
        risk_level:,
        executor: "codex",
        execution_mode: "cloud",
        profile: execution_profile,
        existing_task:,
        latest_snapshot: latest_snapshot?,
        metadata: result_metadata
      )
    end

    private

    attr_reader :candidate, :metadata, :brief, :reasons, :require_approval, :ignore_existing_task

    def evaluate
      reasons << "not_article_opportunity_candidate" unless self.class.article_opportunity_candidate?(candidate)
      reasons << "not_production_candidate" unless truthy?(metadata["production_candidate"])
      reasons << "execution_brief_missing" if brief.blank?
      reasons << "not_approved" if require_approval && candidate.status.to_s != "approved"
      reasons << "inactive_candidate" if candidate.status.to_s.in?(ActionCandidate::INACTIVE_STATUSES)
      reasons << "already_executed" if candidate.executed?
      reasons << "opportunity_type_not_allowed" unless opportunity_type.in?(ALLOWED_TYPES)
      reasons << "blocked_opportunity_type" if opportunity_type.in?(BLOCKED_TYPES)
      reasons << "codex_not_eligible" unless brief.dig("execution", "codex_eligible") == true || metadata["codex_eligible"] == true
      reasons << "human_required" if brief.dig("execution", "human_required") == true
      reasons << "research_required" if brief.dig("execution", "research_required") == true
      reasons << "missing_information_present" if important_missing_information.any?
      reasons << "invalid_target_type" unless brief.dig("target", "target_type").to_s == "existing_article"
      reasons << "target_url_invalid" unless safe_target_url?
      reasons << "completion_conditions_missing" if Array(brief["completion_conditions"]).compact_blank.empty?
      reasons << "recommended_changes_missing" if Array(brief["recommended_changes"]).compact_blank.empty?
      reasons << "internal_link_targets_missing" if opportunity_type == "internal_link_addition" && internal_link_candidates.empty?
      reasons << "unsafe_internal_link_target" if unsafe_internal_links.any?
      reasons << "high_factual_risk" if brief.dig("safety", "factual_risk").to_s == "high"
      reasons << "rollback_not_possible_high_risk" if risk_level == "high" && brief.dig("execution", "rollback_possible") == false
      reasons << "repository_missing" unless repository_configured?
      reasons << "execution_profile_missing" unless execution_profile
      reasons << "execution_profile_not_codex_ready" if execution_profile && !execution_profile.codex_ready_for_submission?
      reasons << "risk_limit_exceeded" if execution_profile && !execution_profile.codex_risk_allowed?(risk_level)
      reasons << "active_auto_revision_task_exists" if existing_task
      reasons << "superseded_by_newer_snapshot" unless latest_snapshot?
      reasons << "external_url_detected" if external_url_detected?
    end

    def result_metadata
      {
        "article_opportunity_codex_gate" => {
          "eligible" => reasons.empty?,
          "reasons" => reasons.uniq,
          "risk_level" => risk_level,
          "executor" => "codex",
          "execution_mode" => "cloud",
          "latest_snapshot" => latest_snapshot?,
          "existing_auto_revision_task_id" => existing_task&.id,
          "repository_configured" => repository_configured?,
          "execution_profile_configured" => execution_profile.present?,
          "checked_at" => Time.current.iso8601
        }
      }
    end

    def opportunity_type
      metadata["opportunity_type"].to_s
    end

    def important_missing_information
      Array(brief["missing_information"]).compact_blank
    end

    def risk_level
      @risk_level ||= begin
        return "high" if explicit_high_risk?
        return "medium" if opportunity_type.in?(%w[rank_improvement content_update])
        return "medium" if Array(brief["recommended_changes"]).size > 2

        "low"
      end
    end

    def explicit_high_risk?
      text = [
        candidate.title,
        candidate.description,
        candidate.execution_prompt,
        brief.dig("safety", "prohibited_actions"),
        brief["recommended_changes"]
      ].flatten.compact.join(" ").downcase
      text.match?(/db:migrate|migration|認証|課金|credential|secret|token|delete|destroy|外部api|自動公開/)
    end

    def safe_target_url?
      target_url = brief.dig("target", "target_url").to_s
      return false if target_url.blank?

      uri = URI.parse(target_url)
      SAFE_HOSTS.include?(uri.host.to_s.downcase) && uri.path.to_s.start_with?("/articles/")
    rescue URI::InvalidURIError
      false
    end

    def internal_link_candidates
      Array(brief["recommended_changes"]).flat_map do |change|
        Array(change.to_h.dig("evidence", "candidate_links"))
      end.compact
    end

    def unsafe_internal_links
      internal_link_candidates.reject do |link|
        link = link.to_h
        path = link["path"].to_s
        url = link["url"].to_s
        path.start_with?("/articles/") &&
          url.start_with?("https://suelog.jp/articles/")
      end
    end

    def external_url_detected?
      text = [candidate.title, candidate.description, candidate.execution_prompt, metadata, brief].compact.join(" ")
      text.match?(%r{https?://(?!suelog\.jp|www\.suelog\.jp)[^\s\]")]+})
    end

    def repository_configured?
      execution_profile&.effective_codex_repository_url.present? &&
        execution_profile&.effective_codex_base_branch.present? &&
        execution_profile&.effective_codex_working_branch_prefix.present?
    end

    def execution_profile
      @execution_profile ||= candidate.business&.business_execution_profile&.then { |profile| profile.active? ? profile : nil }
    end

    def existing_task
      return nil if ignore_existing_task

      @existing_task ||= candidate.auto_revision_tasks.where(status: ACTIVE_TASK_STATUSES).order(created_at: :desc).first
    end

    def latest_snapshot?
      return @latest_snapshot if defined?(@latest_snapshot)

      snapshot_id = metadata["snapshot_id"]
      article_id = metadata["article_id"]
      @latest_snapshot = false
      return @latest_snapshot if snapshot_id.blank? || article_id.blank?

      latest = AicooDataSnapshot
        .where(source_type: "article_analytics")
        .where("payload ->> 'business_id' = ?", candidate.business_id.to_s)
        .where("payload ->> 'article_id' = ?", article_id.to_s)
        .order(captured_at: :desc, id: :desc)
        .detect do |snapshot|
          payload = snapshot.payload.to_h
          !payload["snapshot_status"].to_s.in?(%w[archived ignored])
        end

      @latest_snapshot = latest&.id.to_s == snapshot_id.to_s
    end

    def truthy?(value)
      value == true || value.to_s == "true"
    end
  end
end
