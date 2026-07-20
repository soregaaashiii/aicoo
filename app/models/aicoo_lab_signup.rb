class AicooLabSignup < ApplicationRecord
  belongs_to :aicoo_lab_landing_page

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  after_commit :refresh_lovable_learning, on: :create

  private

  def refresh_lovable_learning
    Aicoo::Lovable::LearningRefresher.call(aicoo_lab_landing_page)
  end
end
