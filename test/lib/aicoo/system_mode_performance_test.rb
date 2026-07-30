ENV["RAILS_ENV"] ||= "test"

require "active_support"
require "active_support/core_ext"
require "active_support/notifications"
require "logger"
require "minitest/autorun"
require "rack/mock"
require_relative "../../../lib/aicoo/system_mode_performance"

module Aicoo
  class SystemModePerformanceTest < Minitest::Test
    class CaptureLogger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def info(message)
        messages << message
      end

      def warn(message)
        messages << message
      end
    end

    def setup
      @logger = CaptureLogger.new
      SystemModePerformance.logger = @logger
      SystemModePerformance.install!
    end

    def test_adds_server_timing_and_one_summary_log_to_target_request
      app = lambda do |env|
        env["action_dispatch.request_id"] = "request-123"
        ActiveSupport::Notifications.instrument(
          "process_action.action_controller",
          controller: "Owner::FocusController",
          action: "show",
          status: 200,
          view_runtime: 4.5
        ) do
          sleep 0.001
        end
        [ 200, { "content-type" => "text/html" }, [ "<html>ok</html>" ] ]
      end

      status, headers, body = middleware(app).call(env_for("/owner/focus"))

      assert_equal 200, status
      assert_equal "<html>ok</html>", body.join
      assert_includes headers.fetch("server-timing"), "rack;dur="
      assert_includes headers.fetch("server-timing"), "sql;dur="
      assert_equal 1, @logger.messages.grep(/\A#{Regexp.escape(SystemModePerformance::PREFIX)}/).size

      payload = summary_payload
      assert_equal "request-123", payload.fetch("request_id")
      assert_equal "/owner/focus", payload.fetch("path")
      assert_equal 200, payload.fetch("status")
      assert_equal 0, payload.fetch("insert_count")
      assert_equal 0, payload.fetch("update_count")
      assert_equal 0, payload.fetch("delete_count")
    end

    def test_does_not_measure_non_target_request
      app = ->(_env) { [ 200, { "content-type" => "text/html" }, [ "ok" ] ] }

      _status, headers, _body = middleware(app).call(env_for("/businesses"))

      refute headers.key?("server-timing")
      assert_empty @logger.messages
    end

    def test_measures_only_get_requests_for_the_four_target_paths
      app = ->(_env) { [ 200, {}, [ "ok" ] ] }

      SystemModePerformance::TARGET_PATHS.each do |path|
        _status, headers, _body = middleware(app).call(env_for(path))
        assert_includes headers.fetch("server-timing"), "rack;dur="
      end

      post_env = Rack::MockRequest.env_for("/owner", method: "POST")
      _status, headers, _body = middleware(app).call(post_env)
      refute headers.key?("server-timing")
      assert_equal SystemModePerformance::TARGET_PATHS.size, @logger.messages.size
    end

    def test_aggregates_sql_without_bind_values
      app = lambda do |env|
        env["action_dispatch.request_id"] = "sql-request"
        ActiveSupport::Notifications.instrument(
          "sql.active_record",
          name: "ActionCandidate Load",
          sql: %(SELECT * FROM "action_candidates" WHERE "email" = 'secret@example.com' AND "id" = $1),
          binds: [ "do-not-log" ],
          cached: false
        )
        ActiveSupport::Notifications.instrument(
          "instantiation.active_record",
          class_name: "ActionCandidate",
          record_count: 3
        )
        [ 200, {}, [ "ok" ] ]
      end

      middleware(app).call(env_for("/admin/aicoo_revenue"))

      payload = summary_payload
      assert_equal 1, payload.fetch("sql_count")
      assert_equal 1, payload.fetch("real_sql_count")
      assert_equal 3, payload.fetch("action_candidate_fetched_count")
      serialized = payload.to_json
      refute_includes serialized, "secret@example.com"
      refute_includes serialized, "do-not-log"
      assert_includes serialized, %(FROM \\"action_candidates\\")
    end

    def test_counts_get_writes_without_changing_response
      app = lambda do |_env|
        %w[INSERT UPDATE DELETE].each do |verb|
          ActiveSupport::Notifications.instrument(
            "sql.active_record",
            name: "SQL",
            sql: "#{verb} example_table SET value = 1",
            cached: false
          )
        end
        [ 200, {}, [ "same-body" ] ]
      end

      status, _headers, body = middleware(app).call(env_for("/owner/tasks"))

      assert_equal 200, status
      assert_equal "same-body", body.join
      payload = summary_payload
      assert_equal 1, payload.fetch("insert_count")
      assert_equal 1, payload.fetch("update_count")
      assert_equal 1, payload.fetch("delete_count")
    end

    private

    def middleware(app)
      SystemModePerformance::Middleware.new(app)
    end

    def env_for(path)
      Rack::MockRequest.env_for(path, method: "GET")
    end

    def summary_payload
      JSON.parse(@logger.messages.last.delete_prefix("#{SystemModePerformance::PREFIX} "))
    end
  end
end
