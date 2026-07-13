class AicooAutoRevisionSetting < ApplicationRecord
  DEFAULTS = {
    enabled: true,
    max_tasks_per_run: 5,
    minimum_final_score: 1_000,
    allow_medium_risk: true,
    codex_queue_paused: false,
    created_by_system: true
  }.freeze

  validates :max_tasks_per_run, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 50 }
  validates :minimum_final_score, numericality: { greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!(DEFAULTS)
  end

  def pause_codex_queue!(reason:)
    update!(
      codex_queue_paused: true,
      codex_queue_pause_reason: reason,
      codex_queue_paused_at: Time.current
    )
  end

  def resume_codex_queue!
    update!(
      codex_queue_paused: false,
      codex_queue_pause_reason: nil,
      codex_queue_paused_at: nil
    )
  end
end
