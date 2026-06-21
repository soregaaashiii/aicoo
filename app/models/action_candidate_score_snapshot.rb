class ActionCandidateScoreSnapshot < ApplicationRecord
  belongs_to :action_candidate
  belongs_to :business

  validates :recorded_on, presence: true
  validates :action_candidate_id, uniqueness: { scope: :recorded_on }
  validates :raw_rank, :adjusted_rank, :rank_delta, presence: true

  scope :recent, -> { order(recorded_on: :desc, updated_at: :desc) }
  scope :for_date, ->(date) { where(recorded_on: date) }
  scope :rank_up, -> { where("rank_delta > 0").order(rank_delta: :desc) }
  scope :rank_down, -> { where("rank_delta < 0").order(rank_delta: :asc) }
  scope :largest_multiplier, -> { order(adjustment_multiplier: :desc, judge_adjusted_score: :desc) }
  scope :no_adjustment, -> { where(adjustment_multiplier: 1, generation_source_accuracy: nil, action_type_accuracy: nil) }
end
