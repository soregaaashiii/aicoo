class AicooCodexPromptTargetValidationService
  Result = Data.define(:valid, :errors, :warnings, :missing_items, :target_status, :target_business, :target_repository_name) do
    def valid?
      valid
    end

    def warning?
      target_status == "warning"
    end

    def invalid?
      target_status == "invalid"
    end
  end

  def initialize(auto_revision_task)
    @auto_revision_task = auto_revision_task
    @errors = []
    @warnings = []
    @missing_items = []
  end

  def call
    validate_target_business
    validate_target_repository_fields
    validate_profile unless internal_business?
    validate_prompt_contents if profile&.active?

    Result.new(
      valid: errors.empty?,
      errors:,
      warnings:,
      missing_items: missing_items.uniq,
      target_status: target_status,
      target_business: task.target_business || task.business,
      target_repository_name: task.target_repository_name
    )
  end

  private

  attr_reader :auto_revision_task, :errors, :warnings, :missing_items
  alias task auto_revision_task

  def validate_target_business
    return if task.target_business_id.present? && task.target_business

    add_error("target_business_idが未設定です。", "target_business_id")
  end

  def validate_target_repository_fields
    add_error("target_repository_nameが未設定です。", "target_repository_name") if task.target_repository_name.blank?
    add_error("target_repository_typeが未設定です。", "target_repository_type") if task.target_repository_type.blank?
  end

  def validate_profile
    unless profile
      add_error("BusinessExecutionProfileが未作成です。", "business_execution_profile")
      return
    end

    add_error("BusinessExecutionProfileが無効です。", "active") unless profile.active?
    validate_profile_completeness
    validate_target_matches_profile
  end

  def internal_business?
    (task.target_business || task.business)&.aicoo_internal_codex?
  end

  def validate_profile_completeness
    profile_missing_fields.each do |field|
      add_error("BusinessExecutionProfileの#{field}が未設定です。", field)
    end
  end

  def validate_target_matches_profile
    if task.target_repository_name.present? && profile.repository_name.present? && task.target_repository_name != profile.repository_name
      add_error("target_repository_nameがBusinessExecutionProfileのrepository_nameと一致しません。", "target_repository_name")
    end

    if task.target_repository_type.present? && profile.repository_type.present? && task.target_repository_type != profile.repository_type
      add_error("target_repository_typeがBusinessExecutionProfileのrepository_typeと一致しません。", "target_repository_type")
    end
  end

  def validate_prompt_contents
    profile.forbidden_pattern_lines.each do |pattern|
      next if prompt.include?(pattern)

      add_error("forbidden_patternsの「#{pattern}」がCodex用プロンプトに含まれていません。", "forbidden_patterns")
    end

    return if profile.codex_instructions.blank? || prompt.include?(profile.codex_instructions)

    add_error("codex_instructionsがCodex用プロンプトに含まれていません。", "codex_instructions")
  end

  def profile_missing_fields
    fields = profile.missing_required_fields
    fields << "lint_command" if profile.lint_command.blank?
    fields.uniq
  end

  def profile
    @profile ||= task.business&.business_execution_profile
  end

  def prompt
    @prompt ||= task.codex_prompt.to_s
  end

  def add_error(message, missing_item)
    errors << message
    missing_items << missing_item
  end

  def target_status
    return "invalid" if errors.any?
    return "warning" if warnings.any?

    "valid"
  end
end
