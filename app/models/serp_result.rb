class SerpResult < ApplicationRecord
  belongs_to :serp_analysis

  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
