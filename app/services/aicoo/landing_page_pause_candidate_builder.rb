module Aicoo
  class LandingPagePauseCandidateBuilder
    Candidate = Data.define(:landing_page, :reason, :message, :priority)

    MINIMUM_VIEWS = 100
    LOW_CTA_RATE = 0.01

    def call
      AicooLabLandingPage.publicly_available.find_each.filter_map do |landing_page|
        candidate_for(landing_page)
      end
    end

    private

    def candidate_for(landing_page)
      views = landing_page.view_count
      return if views < MINIMUM_VIEWS

      if landing_page.signup_count.zero?
        Candidate.new(
          landing_page:,
          reason: "conversion_low",
          message: "Signupが0件のため公開停止候補です。",
          priority: "medium"
        )
      elsif landing_page.cta_rate && landing_page.cta_rate < LOW_CTA_RATE
        Candidate.new(
          landing_page:,
          reason: "low_quality",
          message: "CTA率が低いため公開停止候補です。",
          priority: "low"
        )
      end
    end
  end
end
