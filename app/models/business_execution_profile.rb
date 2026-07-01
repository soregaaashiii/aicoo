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

  validates :business_id, uniqueness: true
  validates :execution_type, inclusion: { in: EXECUTION_TYPES }
  validates :repository_type, inclusion: { in: REPOSITORY_TYPES }
  validates :deploy_target, inclusion: { in: DEPLOY_TARGETS }
  validates :auto_deploy_risk_limit, inclusion: { in: RISK_LIMITS }
  validates :default_branch, presence: true

  before_validation :set_defaults

  scope :active, -> { where(active: true) }
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

  def repository_url
    github_repository
  end

  def base_branch
    default_branch
  end

  def working_branch_for(task)
    "#{working_branch_prefix.presence || 'codex/auto-revision'}-#{task.id}"
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
      risk_allowed_for_auto_deploy?(task.risk_level)
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
    self.deploy_target = "render" if deploy_target.blank?
    self.auto_deploy_risk_limit = "low" if auto_deploy_risk_limit.blank?
    self.auto_merge_enabled = false if auto_merge_enabled.nil?
    self.require_manual_approval = true if require_manual_approval.nil?
    self.active = true if active.nil?
    return if forbidden_patterns.present?

    self.forbidden_patterns = DEFAULT_FORBIDDEN_PATTERNS.join("\n")
  end
end
