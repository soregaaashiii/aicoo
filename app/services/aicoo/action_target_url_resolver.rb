module Aicoo
  class ActionTargetUrlResolver
    METRIC_NAMES = %w[
      clicks
      phone_clicks
      map_clicks
      affiliate_clicks
    ].freeze
    METRIC_PREFIX_SEGMENTS = %w[analytics metric metrics map phone affiliate clicks].freeze

    class << self
      def call(value, require_known_route: true)
        new(value, require_known_route:).call
      end

      def metric_reference?(value)
        new(value, require_known_route: false).metric_reference?
      end

      def known_route_path?(value)
        new(value, require_known_route: true).known_route_path?
      end
    end

    def initialize(value, require_known_route: true)
      @value = value.to_s.strip
      @require_known_route = require_known_route
    end

    def call
      return nil if value.blank?
      return nil if metric_reference?
      return value if external_url?
      return normalized_path if known_route_path?
      return normalized_path unless require_known_route

      nil
    end

    def metric_reference?
      normalized = normalized_metric_value
      return true if METRIC_NAMES.include?(normalized)

      segments = normalized.split("/")
      return false if segments.empty?

      metric_segments = segments.select { |segment| METRIC_NAMES.include?(segment) }
      metric_segments.any? && (segments - metric_segments - METRIC_PREFIX_SEGMENTS).empty?
    end

    def known_route_path?
      path = normalized_path
      return false unless path.start_with?("/")

      route_patterns.any? { |pattern| pattern.match?(path) }
    end

    private

    attr_reader :value, :require_known_route

    def external_url?
      value.match?(/\Ahttps?:\/\//i)
    end

    def normalized_path
      @normalized_path ||= begin
        path = value.split(/[?#]/, 2).first.to_s
        path.start_with?("/") ? path : "/#{path}"
      end
    end

    def normalized_metric_value
      value
        .delete_prefix("/")
        .split(/[?#]/, 2)
        .first
        .to_s
        .downcase
        .squeeze("/")
    end

    def route_patterns
      @route_patterns ||= Rails.application.routes.routes.filter_map do |route|
        spec = route.path.spec.to_s
        next if spec.blank?

        route_path = spec.sub(/\(\.:format\)\z/, "")
        next if route_path.start_with?("/rails/")

        pattern = Regexp.escape(route_path).gsub(/:[^\/]+/, "[^/]+")
        /\A#{pattern}\z/
      end
    end
  end
end
