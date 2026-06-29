class BusinessExecutionProfile < ApplicationRecord
  EXECUTION_TYPES = %w[aicoo_internal external_repo].freeze
  REPOSITORY_TYPES = %w[rails nextjs static_site wordpress api other].freeze
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
      auto_deploy_enabled:
    }
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
    self.active = true if active.nil?
    return if forbidden_patterns.present?

    self.forbidden_patterns = DEFAULT_FORBIDDEN_PATTERNS.join("\n")
  end
end
