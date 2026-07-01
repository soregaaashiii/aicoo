class Business < ApplicationRecord
  STATUSES = %w[idea researching building launched paused sold withdrawn].freeze
  LIFECYCLE_STAGES = %w[idea lp_validation mvp production scaling pivot archived].freeze
  RESOURCE_STATUSES = %w[active watch paused archived].freeze
  AUTO_REVISION_MODES = %w[manual approval automatic].freeze
  AUTO_DEPLOY_MODES = %w[manual approval automatic].freeze
  AUTO_BUILD_RISK_LEVELS = %w[low medium high].freeze
  NEW_LP_AUTO_DEPLOY_LIFECYCLE_STAGES = %w[idea lp_validation mvp].freeze
  NEW_LP_AUTO_DEPLOY_EXCLUDED_NAMES = [
    "吸えログ",
    "AICOO",
    "AICOO Analytics Import"
  ].freeze
  SYSTEM_BUSINESS_NAMES = [
    "AICOO Analytics Import"
  ].freeze

  has_many :action_candidates, dependent: :destroy
  has_many :opportunity_discovery_items, dependent: :nullify
  has_many :auto_revision_tasks, dependent: :destroy
  has_many :auto_build_tasks, dependent: :destroy
  has_many :auto_revision_run_logs, dependent: :destroy
  has_many :codex_prompt_drafts, dependent: :nullify
  has_many :action_results, dependent: :destroy
  has_many :action_candidate_score_snapshots, dependent: :destroy
  has_many :meta_evaluation_snapshots, dependent: :destroy
  has_many :ai_evaluation_runs, dependent: :destroy
  has_many :data_sources, dependent: :destroy
  has_many :data_imports, through: :data_sources
  has_many :business_data_source_settings, dependent: :destroy
  has_many :serp_analyses, dependent: :destroy
  has_many :revenue_events, dependent: :destroy
  has_many :business_metric_dailies, dependent: :destroy
  has_many :business_activity_logs, dependent: :destroy
  has_many :source_app_connections, dependent: :destroy
  has_many :activity_evaluations, dependent: :destroy
  has_many :business_services, dependent: :destroy
  has_many :analysis_candidates, dependent: :destroy
  has_many :aicoo_lab_landing_pages, dependent: :nullify
  has_many :aicoo_pipeline_runs, dependent: :nullify
  has_one :business_execution_profile, dependent: :destroy
  has_one :business_playbook, dependent: :destroy
  has_one :proxy_score_weight, dependent: :destroy
  has_many :proxy_score_weight_adjustment_logs, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :lifecycle_stage, inclusion: { in: LIFECYCLE_STAGES }
  validates :resource_status, inclusion: { in: RESOURCE_STATUSES }
  validates :auto_revision_mode, inclusion: { in: AUTO_REVISION_MODES }
  validates :auto_deploy_mode, inclusion: { in: AUTO_DEPLOY_MODES }
  validates :auto_build_risk_level, inclusion: { in: AUTO_BUILD_RISK_LEVELS }

  scope :real_businesses, -> { where.not(name: SYSTEM_BUSINESS_NAMES) }
  scope :system_businesses, -> { where(name: SYSTEM_BUSINESS_NAMES) }
  scope :resource_active, -> { where(resource_status: "active") }
  scope :resource_watch, -> { where(resource_status: "watch") }
  scope :resource_paused, -> { where(resource_status: "paused") }
  scope :resource_archived, -> { where(resource_status: "archived") }

  before_validation :set_default_status

  scope :aicoo_created_unlaunched, -> { real_businesses.where(created_by_aicoo: true, launched: false) }

  def system_business?
    name.in?(SYSTEM_BUSINESS_NAMES)
  end

  def change_resource_status!(status, reason:, operator: "owner")
    previous_status = resource_status
    update!(
      resource_status: status,
      resource_status_reason: reason,
      resource_status_changed_at: Time.current,
      next_review_on: Aicoo::ResourceSummary.default_next_review_on(status)
    )
    record_resource_status_activity!(previous_status:, operator:)
  end

  def aicoo_internal_codex?
    return false if business_execution_profile&.execution_type == "external_repo"

    created_by_aicoo?
  end

  def codex_execution_type
    return "aicoo_internal" if aicoo_internal_codex?

    business_execution_profile&.execution_type.presence || "external_repo"
  end

  def codex_execution_label
    aicoo_internal_codex? ? "AICOO内部プロジェクト（接続済み）" : "外部Repository"
  end

  def setup_incomplete?
    created_by_aicoo? && !launched?
  end

  def manual_auto_revision?
    auto_revision_mode == "manual"
  end

  def approval_auto_revision?
    auto_revision_mode == "approval"
  end

  def automatic_auto_revision?
    auto_revision_mode == "automatic"
  end

  def manual_auto_deploy?
    auto_deploy_mode == "manual"
  end

  def approval_auto_deploy?
    auto_deploy_mode == "approval"
  end

  def automatic_auto_deploy?
    auto_deploy_mode == "automatic"
  end

  def lab_auto_build_candidate?
    created_by_aicoo? || source.to_s.in?(%w[idea_pipeline aicoo_lab]) || aicoo_lab_landing_pages.exists?
  end

  def new_lp_auto_deploy_candidate?
    real_new_lp_business? && new_lp_auto_deploy_enabled? && !auto_deploy_suspended?
  end

  def real_new_lp_business?
    NEW_LP_AUTO_DEPLOY_LIFECYCLE_STAGES.include?(lifecycle_stage) &&
      !production_like_business? &&
      !revenue_recorded? &&
      !system_business? &&
      NEW_LP_AUTO_DEPLOY_EXCLUDED_NAMES.exclude?(name)
  end

  def production_like_business?
    lifecycle_stage.in?(%w[production scaling archived]) || status.in?(%w[sold withdrawn])
  end

  def suspend_auto_deploy!(reason:)
    update!(
      auto_deploy_suspended: true,
      auto_deploy_suspended_at: Time.current,
      auto_deploy_suspended_reason: reason
    )
  end

  def current_month_revenue
    revenue_amount(current_month_range)
  end

  def current_month_expense
    expense_amount(current_month_range)
  end

  def current_month_profit
    current_month_revenue - current_month_expense
  end

  def cumulative_revenue
    revenue_amount
  end

  def cumulative_expense
    expense_amount
  end

  def cumulative_profit
    cumulative_revenue - cumulative_expense
  end

  def revenue_amount(range = nil)
    scoped_revenue_events(range).revenue.sum(:amount)
  end

  def expense_amount(range = nil)
    scoped_revenue_events(range).expense.sum(:amount)
  end

  def current_month_proxy_score
    proxy_score(current_month_range)
  end

  def recent_7d_proxy_score
    recent_proxy_score(7)
  end

  def recent_30d_proxy_score
    recent_proxy_score(30)
  end

  def cumulative_proxy_score
    proxy_score
  end

  def proxy_score(range = nil)
    scoped_business_metric_dailies(range).sum(&:proxy_score)
  end

  def current_month_metric_total(metric)
    metric_total(metric, current_month_range)
  end

  def cumulative_metric_total(metric)
    metric_total(metric)
  end

  def revenue_recorded?
    revenue_events.revenue.exists?
  end

  def evaluation_focus
    revenue_recorded? ? "profit" : "proxy_score"
  end

  def codex_project_key
    return "aicoo_internal" if aicoo_internal_codex?

    project_key.presence || business_execution_profile&.repository_name
  end

  def codex_local_project_path
    return Rails.root.to_s if aicoo_internal_codex?

    local_project_path.presence || business_execution_profile&.repository_path
  end

  def codex_repository_name
    return ENV.fetch("GITHUB_REPOSITORY", "soregaaashiii/aicoo") if aicoo_internal_codex?

    repository_name.presence || business_execution_profile&.repository_name
  end

  def codex_verification_commands
    Array(default_verification_commands).presence ||
      business_execution_profile_commands ||
      CodexPromptDraft::DEFAULT_VERIFICATION_COMMANDS
  end

  def codex_execution_target_config
    profile = business_execution_profile
    if aicoo_internal_codex?
      return {
        execution_type: "aicoo_internal",
        github_repo: ENV.fetch("GITHUB_REPOSITORY", "soregaaashiii/aicoo"),
        local_project_path: Rails.root.to_s,
        target_slug: source_target_slug,
        target_paths: aicoo_internal_target_paths,
        test_command: codex_verification_commands.first,
        deploy_command: nil,
        default_branch: "main",
        auto_deploy_enabled: false
      }
    end

    {
      execution_type: profile&.execution_type.presence || "external_repo",
      github_repo: profile&.github_repo.presence || repository_name.presence,
      local_project_path: profile&.local_project_path.presence || local_project_path.presence,
      target_slug: profile&.target_slug.presence,
      target_paths: Array(profile&.target_paths),
      test_command: profile&.test_command.presence || codex_verification_commands.first,
      deploy_command: profile&.deploy_command.presence,
      default_branch: profile&.default_branch.presence || "main",
      auto_deploy_enabled: profile&.auto_deploy_enabled? || false
    }
  end

  def current_proxy_score_weight
    ProxyScoreWeight.for_business(self)
  end

  private

  def set_default_status
    self.status = "idea" if status.blank?
    self.lifecycle_stage = infer_lifecycle_stage if lifecycle_stage.blank?
    self.resource_status = "active" if resource_status.blank?
    self.auto_revision_mode = "manual" if auto_revision_mode.blank?
    self.auto_deploy_mode = "manual" if auto_deploy_mode.blank?
    self.auto_build_risk_level = "low" if auto_build_risk_level.blank?
  end

  def record_resource_status_activity!(previous_status:, operator:)
    business_activity_logs.create!(
      activity_type: "resource_status_changed",
      source_app: "aicoo",
      source_method: "logger",
      resource_type: "Business",
      resource_id: id.to_s,
      title: "運用状態を#{resource_status}へ変更",
      occurred_at: Time.current,
      detected_at: Time.current,
      diff_summary: "#{previous_status} から #{resource_status} へ変更しました。",
      idempotency_key: "resource_status:business:#{id}:#{resource_status}:#{resource_status_changed_at.to_i}",
      before_snapshot: { "resource_status" => previous_status },
      after_snapshot: { "resource_status" => resource_status },
      metadata: {
        "operator" => operator,
        "reason" => resource_status_reason,
        "next_review_on" => next_review_on&.iso8601
      }
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def infer_lifecycle_stage
    return "archived" if status == "withdrawn"
    return "scaling" if status == "sold"
    return "production" if status == "launched"
    return "mvp" if status == "building"
    return "lp_validation" if aicoo_lab_landing_pages.publicly_available.exists?

    "idea"
  end

  def current_month_range
    Date.current.beginning_of_month..Date.current.end_of_month
  end

  def recent_proxy_score(days)
    proxy_score((days - 1).days.ago.to_date..Date.current)
  end

  def scoped_revenue_events(range)
    scope = revenue_events
    range ? scope.where(occurred_on: range) : scope
  end

  def scoped_business_metric_dailies(range)
    scope = business_metric_dailies
    range ? scope.where(recorded_on: range) : scope
  end

  def business_execution_profile_commands
    profile = business_execution_profile
    return unless profile

    [
      profile.test_command,
      profile.lint_command
    ].compact_blank.presence
  end

  def source_target_slug
    aicoo_lab_landing_pages.order(updated_at: :desc).first&.published_slug
  end

  def aicoo_internal_target_paths
    [
      "app/models/business.rb",
      "app/models/aicoo_lab_landing_page.rb",
      "app/controllers/admin/aicoo_lab",
      "app/views/admin/aicoo_lab",
      "app/views/public_landing_pages",
      "app/views/businesses"
    ]
  end

  def metric_total(metric, range = nil)
    return 0 unless BusinessMetricDaily::SCORE_WEIGHTS.key?(metric.to_sym)

    scoped_business_metric_dailies(range).sum(metric)
  end
end
