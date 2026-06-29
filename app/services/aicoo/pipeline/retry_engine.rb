module Aicoo
  module Pipeline
    class RetryEngine
      RETRYABLE_STAGES = %w[serp measure improve deploy learning].freeze
      DEFAULT_INTERVALS = [ 5.minutes, 30.minutes, 2.hours, 1.day ].freeze

      def initialize(run)
        @run = run
      end

      def call
        {
          "retryable_stages" => RETRYABLE_STAGES,
          "intervals_seconds" => DEFAULT_INTERVALS.map(&:to_i),
          "retry_count" => run.retry_count,
          "next_retry_at" => next_retry_at&.iso8601,
          "max_retry_count" => DEFAULT_INTERVALS.size
        }
      end

      private

      attr_reader :run

      def next_retry_at
        return unless run.status == "retry_waiting"

        interval = DEFAULT_INTERVALS[[ run.retry_count, DEFAULT_INTERVALS.size - 1 ].min]
        (run.updated_at || Time.current) + interval
      end
    end
  end
end
