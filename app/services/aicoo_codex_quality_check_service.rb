class AicooCodexQualityCheckService
  SUCCESS_PATTERNS = [
    /0 failures/i,
    /all is good/i,
    /no offenses/i,
    /0 failures, 0 errors/i,
    /passed/i
  ].freeze

  FAILURE_PATTERNS = [
    /failure/i,
    /error/i,
    /exception/i,
    /failed/i
  ].freeze

  HIGH_RISK_FILE_PATTERNS = [
    /config\/credentials/i,
    /devise/i,
    /authentication/i,
    /permissions/i,
    /billing/i,
    /payment/i,
    /evaluator/i,
    /daily_runner/i
  ].freeze

  def initialize(auto_revision_task)
    @auto_revision_task = auto_revision_task
  end

  def call
    warnings = []
    quality_score = base_quality_score
    risk_score = base_risk_score
    test_status = detect_test_status
    changed_files = changed_file_lines
    migration_detected = changed_files.any? { |file| file.include?("db/migrate/") }
    high_risk_change_detected = high_risk_change?(changed_files)

    quality_score += 20 if test_status == "passed"
    quality_score -= 35 if test_status == "failed"
    warnings << "テスト失敗またはエラーを検知しました" if test_status == "failed"
    warnings << "テスト成功を確認できません" if test_status == "unknown"

    if migration_detected
      risk_score += 25
      warnings << "migration変更を検知しました"
    end

    if high_risk_change_detected
      risk_score += 35
      quality_score -= 15
      warnings << "高リスク領域の変更を検知しました"
    end

    if auto_revision_task.risk_level == "high"
      risk_score += 20
      warnings << "高リスクタスクです"
    end

    if changed_files.empty?
      quality_score -= 15
      warnings << "変更ファイルが記録されていません"
    end

    quality_score = quality_score.clamp(0, 100)
    risk_score = risk_score.clamp(0, 100)
    result = decide_result(quality_score:, warning_count: warnings.size, test_status:, risk_score:)

    auto_revision_task.create_or_update_codex_quality_check!(
      quality_score:,
      risk_score:,
      test_status:,
      migration_detected:,
      high_risk_change_detected:,
      changed_files_count: changed_files.size,
      warning_count: warnings.size,
      warnings:,
      result:
    )
  end

  private

  attr_reader :auto_revision_task

  def base_quality_score
    auto_revision_task.status == "failed" ? 35 : 65
  end

  def base_risk_score
    case auto_revision_task.risk_level
    when "high"
      50
    when "medium"
      25
    else
      10
    end
  end

  def detect_test_status
    text = [ auto_revision_task.test_result, auto_revision_task.codex_output ].join("\n")
    return "failed" if FAILURE_PATTERNS.any? { |pattern| text.match?(pattern) } && !success_text?(text)
    return "passed" if success_text?(text)

    "unknown"
  end

  def success_text?(text)
    SUCCESS_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def changed_file_lines
    auto_revision_task.changed_files.to_s.lines.map(&:strip).reject(&:blank?).uniq
  end

  def high_risk_change?(changed_files)
    changed_files.any? do |file|
      HIGH_RISK_FILE_PATTERNS.any? { |pattern| file.match?(pattern) }
    end
  end

  def decide_result(quality_score:, warning_count:, test_status:, risk_score:)
    return "failed" if test_status == "failed" || quality_score < 45
    return "review_required" if risk_score >= 70 || warning_count >= 3
    return "passed" if quality_score >= 80 && warning_count.zero?
    return "passed_with_warnings" if quality_score >= 70

    "review_required"
  end
end
