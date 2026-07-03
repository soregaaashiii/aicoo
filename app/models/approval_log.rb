class ApprovalLog < ApplicationRecord
  ACTIONS = %w[approve reject pause archive delete].freeze
  COMMON_STATUSES = %w[draft pending approved running completed rejected archived].freeze

  belongs_to :approvable, polymorphic: true
  belongs_to :business, optional: true

  validates :approvable_type, :approvable_id, :action, :source, :approved_at, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :common_previous_status, inclusion: { in: COMMON_STATUSES }, allow_blank: true
  validates :common_new_status, inclusion: { in: COMMON_STATUSES }, allow_blank: true

  scope :recent, -> { order(approved_at: :desc, created_at: :desc) }
  scope :for_action, ->(action) { where(action:) if action.present? }
end
