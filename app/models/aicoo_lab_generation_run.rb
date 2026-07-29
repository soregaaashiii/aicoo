class AicooLabGenerationRun < ApplicationRecord
  GENERATION_TYPES = %w[candidate_generation lp_generation scoring_assist other].freeze
  STATUSES = %w[draft running succeeded failed].freeze
  PIPELINE_DIAGNOSIS_REFRESH_KEYS = %w[
    pipeline_status
    lovable_error_code
    lovable_error_message
    lovable_result_repository
    lovable_result_branch
    source_commit_sha
    github_webhook_commit_sha
    github_webhook_received_at
    github_webhook_receipts
    publication
    measurement_checked_at
    measurement_sources
    learning_status
    learning_completed_at
    pipeline_recovery_status
  ].freeze

  has_many :aicoo_lab_ai_drafts, foreign_key: :generation_run_id, dependent: :destroy, inverse_of: :generation_run

  validates :generation_type, inclusion: { in: GENERATION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :generated_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }

  after_commit :refresh_pipeline_diagnosis_snapshot, on: %i[create update], if: :pipeline_diagnosis_refresh_required?

  private

  def refresh_pipeline_diagnosis_snapshot
    Aicoo::Lovable::PipelineDiagnosisRefresher.call(
      generation_run: self,
      source: pipeline_diagnosis_refresh_source
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[PipelineDiagnosisSnapshot] run_id=#{id} source=#{pipeline_diagnosis_refresh_source} " \
      "error=#{e.class}: #{e.message}"
    )
  end

  def pipeline_diagnosis_refresh_required?
    return false unless generation_type == "lp_generation"
    return false unless metadata.to_h["pipeline"] == Aicoo::Lovable::VersionRepository::PIPELINE_KEY
    return true if previous_changes.key?("id")
    return false unless previous_changes.key?("metadata")

    old_metadata, new_metadata = previous_changes.fetch("metadata").map(&:to_h)
    PIPELINE_DIAGNOSIS_REFRESH_KEYS.any? { |key| old_metadata[key] != new_metadata[key] }
  end

  def pipeline_diagnosis_refresh_source
    old_metadata = previous_changes.fetch("metadata", [ {}, {} ]).first.to_h
    new_metadata = metadata.to_h
    return "webhook" if old_metadata["github_webhook_received_at"] != new_metadata["github_webhook_received_at"]
    if old_metadata["measurement_checked_at"] != new_metadata["measurement_checked_at"] ||
        old_metadata["learning_completed_at"] != new_metadata["learning_completed_at"]
      return "daily_run"
    end
    return "repository_registration" if new_metadata["repository_import"] == true && new_metadata["pipeline_status"] == "artifact_fetching"

    "pipeline_state_change"
  end
end
