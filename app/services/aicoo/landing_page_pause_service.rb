module Aicoo
  class LandingPagePauseService
    def self.pause(landing_page, pause_reason:, operator:, comment: nil, metadata: {})
      new(landing_page).pause(pause_reason:, operator:, comment:, metadata:)
    end

    def self.resume(landing_page, operator:, comment: nil, metadata: {})
      new(landing_page).resume(operator:, comment:, metadata:)
    end

    def initialize(landing_page)
      @landing_page = landing_page
    end

    def pause(pause_reason:, operator:, comment: nil, metadata: {})
      landing_page.pause!(
        reason: pause_reason,
        operator:,
        comment:,
        metadata:
      )
      landing_page
    end

    def resume(operator:, comment: nil, metadata: {})
      landing_page.resume!(
        operator:,
        comment:,
        metadata:
      )
      landing_page
    end

    private

    attr_reader :landing_page
  end
end
