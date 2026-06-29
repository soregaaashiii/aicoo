module Aicoo
  module Pipeline
    class WaitingEngine
      MEASURE_WAIT_DAYS = 30
      MEASURE_WAIT_PV = 1_000

      def initialize(subject)
        @subject = subject
      end

      def call
        return no_wait unless landing_page&.publicly_visible?
        return no_wait if landing_page.view_count >= MEASURE_WAIT_PV

        wait_until = landing_page.published_at&.+(MEASURE_WAIT_DAYS.days)
        return no_wait if wait_until.blank? || wait_until <= Time.current

        {
          "waiting" => true,
          "waiting_until" => wait_until.iso8601,
          "reason" => "published_sample_window",
          "message" => "公開後30日または1000PVまでMeasureを待機します。",
          "current_pv" => landing_page.view_count,
          "target_pv" => MEASURE_WAIT_PV
        }
      end

      private

      attr_reader :subject

      def landing_page
        @landing_page ||= if subject.is_a?(IdeaPipelineItem)
          subject.aicoo_lab_landing_page
        elsif subject.is_a?(Business)
          subject.aicoo_lab_landing_pages.publicly_available.order(updated_at: :desc).first
        end
      end

      def no_wait
        { "waiting" => false }
      end
    end
  end
end
