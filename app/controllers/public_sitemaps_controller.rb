class PublicSitemapsController < ApplicationController
  def show
    AicooLabLandingPage.publish_due!
    @landing_pages = AicooLabLandingPage.publicly_available.order(published_at: :desc, created_at: :desc)

    render formats: :xml
  end
end
