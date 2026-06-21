class AicooLabSignup < ApplicationRecord
  belongs_to :aicoo_lab_landing_page

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
