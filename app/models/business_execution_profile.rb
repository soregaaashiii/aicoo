class BusinessExecutionProfile < ApplicationRecord
  EXECUTION_TYPES = %w[aicoo_internal external_repo].freeze
  REPOSITORY_TYPES = %w[rails nextjs static_site wordpress api other].freeze
  DEPLOY_TARGETS = %w[render github_pages vercel netlify manual other].freeze
  RISK_LIMITS = %w[low medium high].freeze
  RISK_RANK = { "low" => 1, "medium" => 2, "high" => 3 }.freeze
  DEFAULT_FORBIDDEN_PATTERNS = [
    "db:drop",
    "db:reset",
    "drop database"
  ].freeze
  REQUIRED_FIELDS = %w[
    repository_name
    repository_type
    repository_path
    github_repository
    test_command
    deploy_command
  ].freeze

  belongs_to :business
  has_many :codex_submissions, dependent: :restrict_with_exception

  validates :business_id, uniqueness: true
  validates :execution_type, inclusion: { in: EXECUTION_TYPES }
  validates :repository_type, inclusion: { in: REPOSITORY_TYPES }
  validates :deploy_target, inclusion: { in: DEPLOY_TARGETS }
  validates :auto_deploy_risk_limit, inclusion: { in: RISK_LIMITS }
  validates :codex_risk_limit, inclusion: { in: RISK_LIMITS }
  validates :default_branch, presence: true
  validates :codex_base_branch, presence: true
  validates :codex_working_branch_prefix, presence: true

  before_validation :set_defaults

  scope :active, -> { where(active: true) }
  scope :codex_enabled, -> { where(codex_enabled: true) }
  scope :recent, -> { order(created_at: :desc) }

  def forbidden_pattern_lines
    forbidden_patterns.to_s.lines.map(&:strip).reject(&:blank?)
  end

  def display_repository_name
    repository_name.presence || github_repository.presence || repository_path.presence || "-"
  end

  def github_repo
    github_repository
  end

  def local_project_path
    repository_path
  end

  def target_paths_text
    Array(target_paths).join("\n")
  end

  def target_paths_text=(value)
    self.target_paths = value.to_s.lines.map(&:strip).reject(&:blank?)
  end

  def execution_target_config
    {
      execution_type:,
      github_repo: github_repo.presence,
      local_project_path: local_project_path.presence,
      target_slug: target_slug.presence,
      target_paths: Array(target_paths),
      test_command: test_command.presence,
      deploy_command: deploy_command.presence,
      default_branch:,
      working_branch_prefix:,
      deploy_target:,
      render_service_name: render_service_name.presence,
      auto_deploy_enabled:,
      auto_merge_enabled:,
      auto_deploy_risk_limit:,
      require_manual_approval:,
      production_url: production_url.presence,
      health_check_url: health_check_url.presence
    }
  end

  def codex_cloud_config
    {
      codex_enabled:,
      workspace_name: codex_workspace_name.presence,
      project_folder: codex_project_folder.presence,
      repository_url: effective_codex_repository_url,
      base_branch: effective_codex_base_branch,
      working_branch_prefix: effective_codex_working_branch_prefix,
      auto_submit_enabled: codex_auto_submit_enabled?,
      auto_pr_enabled: codex_auto_pr_enabled?,
      auto_merge_enabled: codex_auto_merge_enabled?,
      auto_deploy_enabled: codex_auto_deploy_enabled?,
      risk_limit: codex_risk_limit,
      notes: codex_notes.presence
    }
  end

  def effective_codex_repository_url
    codex_repository_url.presence || github_repository.presence
  end

  def effective_codex_base_branch
    codex_base_branch.presence || default_branch.presence || "main"
  end

  def effective_codex_working_branch_prefix
    codex_working_branch_prefix.presence || working_branch_prefix.presence || "aicoo/"
  end

  def codex_required_missing_fields
    missing = []
    missing << "Codex作業フォルダ" if codex_project_folder.blank?
    missing << "Repository URL" if effective_codex_repository_url.blank?
    missing << "Base Branch" if effective_codex_base_branch.blank?
    missing
  end

  def codex_ready_for_submission?
    active? && codex_enabled? && codex_required_missing_fields.empty?
  end

  def codex_risk_allowed?(risk_level)
    RISK_RANK.fetch(risk_level.to_s, 99) <= RISK_RANK.fetch(codex_risk_limit, 1)
  end

  def repository_url
    github_repository
  end

  def base_branch
    default_branch
  end

  def working_branch_for(task)
    "#{working_branch_prefix.presence || 'codex/auto-revision'}-#{task.id}"
  end

  def codex_working_branch_for(task)
    business_key = task.business&.then { |record| record.respond_to?(:slug) ? record.slug.presence : nil } || task.business_id
    title_slug = task.title.to_s.parameterize.presence || "task"
    prefix = effective_codex_working_branch_prefix
    prefix = "#{prefix}/" unless prefix.end_with?("/")
    "#{prefix}#{business_key}/#{task.id}-#{title_slug.truncate(40, omission: '')}"
  end

  def risk_allowed_for_auto_deploy?(risk_level)
    return false if risk_level == "high"

    RISK_RANK.fetch(risk_level.to_s, 99) <= RISK_RANK.fetch(auto_deploy_risk_limit, 1)
  end

  def auto_merge_allowed_for?(task)
    auto_merge_enabled? && auto_deploy_allowed_for?(task)
  end

  def auto_deploy_allowed_for?(task)
    active? &&
      auto_deploy_enabled? &&
      !require_manual_approval? &&
      risk_allowed_for_auto_deploy?(task.risk_level) &&
      Aicoo::NewLpAutoDeployPolicy.new(task).allowed?
  end

  def deploy_flow_for(task)
    return "prompt_only_high_risk" if task.risk_level == "high"
    return "draft_pr_only" unless auto_deploy_enabled?
    return "pr_manual_merge" unless auto_merge_allowed_for?(task)

    "auto_merge_and_render_deploy"
  end

  def deploy_flow_label_for(task)
    {
      "prompt_only_high_risk" => "高リスクのためプロンプト生成のみ",
      "draft_pr_only" => "PR作成までで停止",
      "pr_manual_merge" => "PR作成後に手動merge/deploy判断",
      "auto_merge_and_render_deploy" => "条件一致時にmerge後Render自動デプロイ"
    }.fetch(deploy_flow_for(task))
  end

  def coverage_status
    return "inactive" unless active?
    return "configured" if missing_required_fields.empty?

    "incomplete"
  end

  def missing_required_fields
    REQUIRED_FIELDS.select { |field| public_send(field).blank? }
  end

  def configured_for_codex?
    coverage_status == "configured"
  end

  private

  def set_defaults
    self.execution_type = "aicoo_internal" if execution_type.blank?
    self.repository_type = "other" if repository_type.blank?
    self.default_branch = "main" if default_branch.blank?
    self.working_branch_prefix = "codex/auto-revision" if working_branch_prefix.blank?
    self.codex_base_branch = default_branch.presence || "main" if codex_base_branch.blank?
    self.codex_working_branch_prefix = "aicoo/" if codex_working_branch_prefix.blank?
    self.codex_risk_limit = "low" if codex_risk_limit.blank?
    self.codex_auto_pr_enabled = true if codex_auto_pr_enabled.nil?
    self.codex_auto_submit_enabled = false if codex_auto_submit_enabled.nil?
    self.codex_auto_merge_enabled = false if codex_auto_merge_enabled.nil?
    self.codex_auto_deploy_enabled = false if codex_auto_deploy_enabled.nil?
    self.deploy_target = "render" if deploy_target.blank?
    self.auto_deploy_risk_limit = "low" if auto_deploy_risk_limit.blank?
    self.auto_merge_enabled = false if auto_merge_enabled.nil?
    self.require_manual_approval = true if require_manual_approval.nil?
    self.active = true if active.nil?
    return if forbidden_patterns.present?

    self.forbidden_patterns = DEFAULT_FORBIDDEN_PATTERNS.join("\n")
  end
end
