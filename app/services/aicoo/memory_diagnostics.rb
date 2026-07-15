require "json"

module Aicoo
  class MemoryDiagnostics
    PREFIX = "[MemoryDiagnostics]".freeze
    WARNING_PREFIX = "[MemoryDiagnostics][WARNING]".freeze
    DEFAULT_WARNING_THRESHOLD_MB = 50.0
    SECRET_KEY_PATTERN = /token|secret|password|cookie|authorization|credential|key/i

    class << self
      def measure(name, context: {}, finish: :always)
        return yield unless enabled?

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        started_at_wall = Time.current
        start_rss_mb = current_rss_mb
        error = nil
        log(:start, name:, rss_mb: start_rss_mb, context:) unless finish == :warning_only

        yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        error = e
        raise
      ensure
        if enabled? && started_at
          finish_rss_mb = current_rss_mb
          elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          rss_delta_mb = rss_delta(start_rss_mb, finish_rss_mb)
          warning = warning?(rss_delta_mb)
          event = error ? :error : :finish

          payload = {
            rss_start_mb: start_rss_mb,
            rss_finish_mb: finish_rss_mb,
            rss_delta_mb:,
            elapsed_ms:,
            started_at: started_at_wall&.iso8601,
            finished_at: Time.current.iso8601,
            error_class: error&.class&.name,
            error_message: truncate(error&.message)
          }.compact

          log(event, name:, context:, **payload) if finish != :warning_only || warning || error
          log(:warning, name:, prefix: WARNING_PREFIX, context:, warning_threshold_mb:, **payload) if warning
        end
      end

      def snapshot
        return {} unless enabled?

        {
          rss_mb: current_rss_mb,
          monotonic_started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
        }
      end

      def point(name, context: {}, baseline: nil, **attributes)
        return unless enabled?

        rss_mb = current_rss_mb
        baseline = baseline.to_h
        rss_start_mb = baseline[:rss_mb] || baseline["rss_mb"]
        started_at = baseline[:monotonic_started_at] || baseline["monotonic_started_at"]
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round if started_at

        payload = {
          rss_mb:,
          rss_start_mb:,
          rss_delta_mb: rss_delta(rss_start_mb, rss_mb),
          elapsed_ms:
        }.merge(attributes).compact

        log(:point, name:, context:, **payload)
      end

      def enabled?
        ActiveModel::Type::Boolean.new.cast(ENV["MEMORY_DIAGNOSTICS_ENABLED"])
      end

      def warning_threshold_mb
        value = ENV["MEMORY_DIAGNOSTICS_WARNING_MB"].presence
        parsed = value ? value.to_f : DEFAULT_WARNING_THRESHOLD_MB
        parsed.positive? ? parsed : DEFAULT_WARNING_THRESHOLD_MB
      rescue StandardError
        DEFAULT_WARNING_THRESHOLD_MB
      end

      def current_rss_mb
        rss_kb = linux_rss_kb || ps_rss_kb
        return unless rss_kb

        (rss_kb.to_d / 1024).round(1).to_f
      rescue StandardError => e
        Rails.logger.debug("#{PREFIX} rss_sample_skipped error_class=#{e.class.name} error_message=#{truncate(e.message)}")
        nil
      end

      private

      def warning?(rss_delta_mb)
        rss_delta_mb.present? && rss_delta_mb >= warning_threshold_mb
      end

      def rss_delta(start_rss_mb, finish_rss_mb)
        return if start_rss_mb.nil? || finish_rss_mb.nil?

        (finish_rss_mb.to_d - start_rss_mb.to_d).round(1).to_f
      end

      def linux_rss_kb
        return unless File.exist?("/proc/self/status")

        line = File.foreach("/proc/self/status").find { |item| item.start_with?("VmRSS:") }
        line.to_s[/\d+/]&.to_i
      end

      def ps_rss_kb
        output = IO.popen([ "ps", "-o", "rss=", "-p", Process.pid.to_s ], &:read)
        output.to_s.strip.presence&.to_i
      end

      def log(event, name:, context: {}, prefix: PREFIX, **attributes)
        payload = {
          event: event.to_s,
          name: name.to_s,
          pid: Process.pid,
          timestamp: Time.current.iso8601
        }.merge(sanitize_context(context)).merge(attributes.compact)

        Rails.logger.info("#{prefix} #{payload.to_json}")
      rescue StandardError => e
        Rails.logger.debug("#{PREFIX} log_skipped error_class=#{e.class.name} error_message=#{truncate(e.message)}")
      end

      def sanitize_context(context)
        context.to_h.each_with_object({}) do |(key, value), sanitized|
          key_string = key.to_s
          next if key_string.match?(SECRET_KEY_PATTERN)

          sanitized[key_string] = sanitize_value(value)
        end
      end

      def sanitize_value(value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric
          value
        when Time, Date, DateTime
          value.iso8601
        when Symbol
          value.to_s
        when Array
          value.first(20).map { |item| sanitize_value(item) }
        when Hash
          sanitize_context(value)
        else
          truncate(value.to_s)
        end
      end

      def truncate(value)
        return if value.nil?

        value.to_s.squish.truncate(240)
      end
    end
  end
end
