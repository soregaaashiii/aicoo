class AicooLabLandingPageSlugHistory < ApplicationRecord
  belongs_to :aicoo_lab_landing_page

  validates :slug, presence: true, uniqueness: true
end
