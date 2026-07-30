require "json"
require "net/http"
require "set"

module Aicoo
  module SystemModePerformance
    PREFIX = "[SystemModePerformance]".freeze
    THREAD_KEY = :aicoo_system_mode_performance_tracker
    TARGET_PATHS = Set.new(
      [
        "/owner",
        "/owner/focus",
        "/owner/tasks",
        "/admin/aicoo_revenue"
      ]
    ).freeze
    SQL_SHAPE_LIMIT = 600
    CALLER_LIMIT = 30

    SERVICE_METHODS = [
      [ "Aicoo::TodayActionBoard", :call, "TodayActionBoard" ],
      [ "Aicoo::ActionExpectedValueRanking", :call, "ActionExpectedValueRanking" ],
      [ "Aicoo::OwnerDecisionSummary", :call, "OwnerDecisionSummary" ],
      [ "Aicoo::OwnerTaskInbox", :call, "OwnerTaskInbox" ],
      [ "Aicoo::OwnerTaskDigest", :call, "OwnerTaskDigest" ],
      [ "Aicoo::OwnerFocusHome", :call, "OwnerFocusHome" ],
      [ "Aicoo::OwnerExecutionQueueSummary", :call, "OwnerExecutionQueueSummary" ],
      [ "Aicoo::LearningLoopQualityReport", :call, "LearningLoopQualityReport" ],
      [ "Aicoo::DiscoverySourcePerformanceReport", :call, "DiscoverySourcePerformanceReport" ],
      [ "Aicoo::LearningReportRecommendation", :call, "LearningReportRecommendation" ],
      [ "Aicoo::OpportunityDiscoverySummary", :call_for_owner_home, "OpportunityDiscoverySummary" ],
      [ "Aicoo::OpportunityFocusQueue", :call, "OpportunityFocusQueue" ],
      [ "Aicoo::ExploreSummary", :call_for_owner_home, "ExploreSummary" ],
      [ "Aicoo::ExploreDailyRoutine", :call, "ExploreDailyRoutine" ],
      [ "Aicoo::AnalysisMonitor", :call_for_owner_home, "AnalysisMonitor" ],
      [ "DashboardSummaryService", :call_for_owner_home, "DashboardSummaryService" ],
      [ "Aicoo::LongRunningOperationMonitor", :call, "operation_status" ],
      [ "Aicoo::DailyRunExecutionStatus", :call, "load_daily_run_execution_status" ]
    ].freeze

    CONTROLLER_ACTIONS = [
      [ "Owner::DashboardController", :show ],
      [ "Owner::FocusController", :show ],
      [ "Owner::TasksController", :index ],
      [ "Admin::AicooRevenueController", :show ]
    ].freeze

    BEFORE_ACTIONS = %i[
      protect_aicoo_management_area
      set_robots_header
      load_daily_run_execution_status
      load_long_running_operation_monitor
    ].freeze

    SORT_METHODS = [
      [ "Aicoo::ActionExpectedValueRanking", :ranked_items, "today_ranking" ],
      [ "Aicoo::OwnerTaskInbox", :sorted_tasks, "owner_tasks" ],
      [ "Aicoo::OwnerDecisionSummary", :action_type_adoption_rates, "decision_action_type" ],
      [ "Aicoo::OwnerDecisionSummary", :risk_level_execution_rates, "decision_risk" ],
      [ "Aicoo::LearningLoopQualityReport", :strongest_action_types, "quality_strongest" ],
      [ "Aicoo::LearningLoopQualityReport", :weakest_action_types, "quality_weakest" ],
      [ "Aicoo::LearningLoopQualityReport", :most_overestimated_actions, "quality_overestimated" ],
      [ "Aicoo::LearningLoopQualityReport", :most_underestimated_actions, "quality_underestimated" ],
      [ "Aicoo::DiscoverySourcePerformanceReport", :strongest_sources, "discovery_strongest" ],
      [ "Aicoo::DiscoverySourcePerformanceReport", :weakest_sources, "discovery_weakest" ],
      [ "DashboardSummaryService", :top_action_candidates, "dashboard_candidates" ],
      [ "DashboardSummaryService", :owner_today_tasks, "dashboard_today" ],
      [ "DashboardSummaryService", :owner_business_rankings, "dashboard_businesses" ]
    ].freeze

    class << self
      attr_writer :logger

      def install!
        return if @installed

        install_notification_subscribers
        install_method_instrumentation
        install_connection_checkout_instrumentation
        install_net_http_instrumentation
        @installed = true
      end

      def current
        Thread.current.thread_variable_get(THREAD_KEY)
      end

      def with_tracker(tracker)
        previous = current
        Thread.current.thread_variable_set(THREAD_KEY, tracker)
        yield
      ensure
        Thread.current.thread_variable_set(THREAD_KEY, previous)
      end

      def target_request?(env)
        env["REQUEST_METHOD"] == "GET" && TARGET_PATHS.include?(env["PATH_INFO"].to_s)
      end

      def measure_service(name)
        tracker = current
        return yield unless tracker

        tracker.measure_service(name) { yield }
      end

      def measure_controller_action(name)
        tracker = current
        return yield unless tracker

        tracker.measure_controller_action(name) { yield }
      end

      def measure_before_action(name)
        tracker = current
        return yield unless tracker

        tracker.measure_before_action(name) { yield }
      end

      def measure_db_checkout
        tracker = current
        return yield unless tracker

        tracker.measure_db_checkout { yield }
      end

      def measure_external_http(http)
        tracker = current
        return yield unless tracker

        tracker.measure_external_http(http) { yield }
      end

      def record_sort(name)
        current&.record_sort(name)
      end

      def record_metadata_access(record)
        current&.record_metadata_access(record)
      end

      def logger
        @logger || (defined?(Rails) ? Rails.logger : nil)
      end

      private

      def install_notification_subscribers
        ActiveSupport::Notifications.monotonic_subscribe("start_processing.action_controller") do |_name, _start, _finish, _id, payload|
          current&.controller_started(payload)
        end
        ActiveSupport::Notifications.monotonic_subscribe("process_action.action_controller") do |_name, start, finish, _id, payload|
          current&.controller_finished((finish - start) * 1000, payload)
        end
        ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, start, finish, _id, payload|
          current&.record_sql((finish - start) * 1000, payload)
        end
        ActiveSupport::Notifications.monotonic_subscribe("instantiation.active_record") do |_name, _start, _finish, _id, payload|
          current&.record_instantiation(payload)
        end
        ActiveSupport::Notifications.monotonic_subscribe("render_partial.action_view") do |_name, _start, _finish, _id, _payload|
          current&.record_partial
        end
      end

      def install_method_instrumentation
        SERVICE_METHODS.each do |class_name, method_name, metric_name|
          wrap_instance_method(class_name, method_name, private_method: false) do |receiver, original, args, kwargs, block|
            measure_service(metric_name) { original.bind_call(receiver, *args, **kwargs, &block) }
          end
        end

        CONTROLLER_ACTIONS.each do |class_name, method_name|
          wrap_instance_method(class_name, method_name, private_method: false) do |receiver, original, args, kwargs, block|
            measure_controller_action("#{class_name}##{method_name}") do
              original.bind_call(receiver, *args, **kwargs, &block)
            end
          end
        end

        BEFORE_ACTIONS.each do |method_name|
          wrap_instance_method("ApplicationController", method_name, private_method: true) do |receiver, original, args, kwargs, block|
            measure_before_action(method_name) { original.bind_call(receiver, *args, **kwargs, &block) }
          end
        end

        SORT_METHODS.each do |class_name, method_name, metric_name|
          wrap_instance_method(class_name, method_name, private_method: true) do |receiver, original, args, kwargs, block|
            record_sort(metric_name)
            original.bind_call(receiver, *args, **kwargs, &block)
          end
        end

        wrap_singleton_method("Aicoo::RequestQueryContext", :normalized_metadata) do |receiver, original, args, kwargs, block|
          record_metadata_access(args.first)
          original.bind_call(receiver, *args, **kwargs, &block)
        end
      end

      def wrap_instance_method(class_name, method_name, private_method:, &instrumentation)
        klass = class_name.safe_constantize
        return unless klass
        return unless klass.method_defined?(method_name) || klass.private_method_defined?(method_name)

        marker = :"@aicoo_system_performance_#{method_name}"
        return if klass.instance_variable_defined?(marker)

        original = klass.instance_method(method_name)
        wrapper = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            instrumentation.call(self, original, args, kwargs, block)
          end
          private method_name if private_method
        end
        klass.prepend(wrapper)
        klass.instance_variable_set(marker, true)
      end

      def wrap_singleton_method(class_name, method_name, &instrumentation)
        klass = class_name.safe_constantize
        return unless klass

        target = klass.singleton_class
        marker = :"@aicoo_system_performance_#{method_name}"
        return if target.instance_variable_defined?(marker)

        original = target.instance_method(method_name)
        wrapper = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            instrumentation.call(self, original, args, kwargs, block)
          end
        end
        target.prepend(wrapper)
        target.instance_variable_set(marker, true)
      end

      def install_connection_checkout_instrumentation
        return unless defined?(ActiveRecord::ConnectionAdapters::ConnectionPool)

        pool_class = ActiveRecord::ConnectionAdapters::ConnectionPool
        return if pool_class.ancestors.include?(ConnectionPoolInstrumentation)

        pool_class.prepend(ConnectionPoolInstrumentation)
      end

      def install_net_http_instrumentation
        return if Net::HTTP.ancestors.include?(NetHttpInstrumentation)

        Net::HTTP.prepend(NetHttpInstrumentation)
      end
    end

    module ConnectionPoolInstrumentation
      private

      def acquire_connection(checkout_timeout)
        Aicoo::SystemModePerformance.measure_db_checkout { super }
      end
    end

    module NetHttpInstrumentation
      def request(...)
        Aicoo::SystemModePerformance.measure_external_http(self) { super }
      end
    end

    class Tracker
      attr_reader :started_monotonic

      def initialize(env)
        @env = env
        @started_monotonic = monotonic
        @started_at = Time.now.utc
        @cpu_started = thread_cpu
        @gc_started = gc_snapshot
        @rss_started_mb = current_rss_mb
        @before_actions = Hash.new { |hash, key| hash[key] = { count: 0, total_ms: 0.0 } }
        @controller_actions = Hash.new { |hash, key| hash[key] = { count: 0, total_ms: 0.0 } }
        @services = Hash.new { |hash, key| hash[key] = { count: 0, total_ms: 0.0 } }
        @service_intervals = []
        @sql_groups = {}
        @sql_total_ms = 0.0
        @sql_count = 0
        @real_sql_count = 0
        @cached_sql_count = 0
        @insert_count = 0
        @update_count = 0
        @delete_count = 0
        @db_checkout_ms = 0.0
        @db_checkout_count = 0
        @instantiation_count = 0
        @action_candidate_instantiation_count = 0
        @partial_count = 0
        @external_calls = {}
        @external_http_ms = 0.0
        @external_http_count = 0
        @sorts = Hash.new(0)
        @metadata_access_count = 0
        @metadata_record_ids = Set.new
        @instrumentation_overhead_ms = 0.0
        @controller_started_at = nil
        @process_action_ms = nil
        @view_ms = nil
        @status = nil
        @finished = false
      end

      def measure_service(name)
        started = monotonic
        yield
      ensure
        if started
          finished = monotonic
          record_duration(@services, name, started, finished)
          @service_intervals << [ started, finished ]
        end
      end

      def measure_controller_action(name)
        started = monotonic
        yield
      ensure
        record_duration(@controller_actions, name, started, monotonic) if started
      end

      def measure_before_action(name)
        started = monotonic
        yield
      ensure
        record_duration(@before_actions, name, started, monotonic) if started
      end

      def measure_db_checkout
        started = monotonic
        yield
      ensure
        if started
          @db_checkout_ms += elapsed_ms(started)
          @db_checkout_count += 1
        end
      end

      def measure_external_http(http)
        started = monotonic
        yield
      ensure
        if started
          duration = elapsed_ms(started)
          @external_http_ms += duration
          @external_http_count += 1
          key = [ external_category(http), app_caller ].join(":")
          row = (@external_calls[key] ||= {
            category: external_category(http),
            caller: app_caller,
            count: 0,
            total_ms: 0.0,
            open_timeout_seconds: safe_timeout(http, :open_timeout),
            read_timeout_seconds: safe_timeout(http, :read_timeout)
          })
          row[:count] += 1
          row[:total_ms] += duration
        end
      end

      def controller_started(payload)
        @controller_started_at ||= monotonic
        @controller_name = payload[:controller].to_s
        @action_name = payload[:action].to_s
      end

      def controller_finished(duration_ms, payload)
        @process_action_ms = duration_ms
        @view_ms = numeric_or_nil(payload[:view_runtime])
        @status = payload[:status]
      end

      def record_sql(duration_ms, payload)
        measure_instrumentation_overhead do
          return if payload[:name].to_s == "SCHEMA"

          sql = payload[:sql].to_s
          return if transaction_sql?(sql)

          cached = payload[:cached] == true
          shape = normalize_sql(sql)
          @sql_count += 1
          @cached_sql_count += 1 if cached
          @real_sql_count += 1 unless cached
          @sql_total_ms += duration_ms
          record_write(sql) unless cached

          row = (@sql_groups[shape] ||= {
            shape:,
            caller: app_caller,
            count: 0,
            cached_count: 0,
            total_ms: 0.0
          })
          row[:count] += 1
          row[:cached_count] += 1 if cached
          row[:total_ms] += duration_ms
        end
      end

      def record_instantiation(payload)
        count = payload[:record_count].to_i
        @instantiation_count += count
        @action_candidate_instantiation_count += count if payload[:class_name].to_s == "ActionCandidate"
      end

      def record_partial
        @partial_count += 1
      end

      def record_sort(name)
        @sorts[name.to_s] += 1
      end

      def record_metadata_access(record)
        return unless record

        @metadata_access_count += 1
        @metadata_record_ids << [ record.class.name, record.object_id ]
      end

      def finish!(status:, headers:, body:)
        return @summary if @finished

        @finished = true
        @status ||= status
        @finished_monotonic = monotonic
        @gc_finished = gc_snapshot
        @cpu_finished = thread_cpu
        @rss_finished_mb = current_rss_mb
        @response_bytes = response_bytes(headers, body)
        @summary = build_summary
      end

      def server_timing
        summary = @summary || build_summary
        metrics = {
          rack: summary[:total_rack_ms],
          app: summary[:rails_process_action_ms],
          pre_controller: summary[:rack_to_controller_ms],
          before_action: summary[:before_action_ms],
          controller: summary[:controller_ms],
          services: summary[:services_ms],
          sql: summary[:sql_total_ms],
          db_checkout: summary[:db_checkout_ms],
          view: summary[:view_ms],
          gc: summary[:gc_ms],
          response_build: summary[:response_build_ms],
          external_http: summary[:external_http_ms],
          ruby_cpu: summary[:ruby_cpu_ms]
        }
        metrics.filter_map do |name, duration|
          next if duration.nil?

          "#{name};dur=#{round(duration)}"
        end.join(", ")
      end

      def log!
        Aicoo::SystemModePerformance.logger&.info("#{PREFIX} #{@summary.to_json}")
      rescue StandardError => error
        Aicoo::SystemModePerformance.logger&.warn(
          "#{PREFIX} log_failed error_class=#{error.class.name}"
        )
      end

      private

      def build_summary
        total_rack_ms = finished_elapsed_ms
        before_action_ms = total_for(@before_actions)
        controller_ms = total_for(@controller_actions)
        services_ms = union_duration_ms(@service_intervals)
        response_build_ms = residual_response_build_ms(
          process_action_ms: @process_action_ms,
          before_action_ms:,
          controller_ms:,
          view_ms: @view_ms
        )
        gc_finished = @gc_finished || gc_snapshot

        {
          timestamp: @started_at.iso8601(6),
          request_id: request_id,
          path: @env["PATH_INFO"].to_s,
          status: @status,
          total_rack_ms: round(total_rack_ms),
          proxy_queue_ms: proxy_queue_ms,
          rack_to_controller_ms: @controller_started_at ? round((@controller_started_at - started_monotonic) * 1000) : nil,
          rails_process_action_ms: round_or_nil(@process_action_ms),
          before_action_ms: round(before_action_ms),
          controller_ms: round(controller_ms),
          view_ms: round_or_nil(@view_ms),
          response_build_ms: round_or_nil(response_build_ms),
          services_ms: round(services_ms),
          sql_total_ms: round(@sql_total_ms),
          sql_count: @sql_count,
          real_sql_count: @real_sql_count,
          cached_sql_count: @cached_sql_count,
          db_checkout_ms: round(@db_checkout_ms),
          db_checkout_count: @db_checkout_count,
          gc_ms: gc_delta(gc_finished, :time),
          gc_count: gc_delta(gc_finished, :count),
          major_gc_count: gc_delta(gc_finished, :major_gc_count),
          minor_gc_count: gc_delta(gc_finished, :minor_gc_count),
          allocations: gc_delta(gc_finished, :total_allocated_objects),
          ruby_cpu_ms: ruby_cpu_ms,
          rss_start_mb: @rss_started_mb,
          rss_finish_mb: @rss_finished_mb,
          rss_delta_mb: rss_delta_mb,
          swap_mb: current_swap_mb,
          response_bytes: @response_bytes,
          partial_count: @partial_count,
          active_record_instantiations: @instantiation_count,
          action_candidate_fetched_count: @action_candidate_instantiation_count,
          action_candidate_sql_count: action_candidate_sql_count,
          metadata_access_count: @metadata_access_count,
          metadata_expansion_target_count: @metadata_record_ids.size,
          ruby_sort_count: @sorts.values.sum,
          ruby_sorts: @sorts.sort.to_h,
          insert_count: @insert_count,
          update_count: @update_count,
          delete_count: @delete_count,
          external_http_ms: round(@external_http_ms),
          external_http_count: @external_http_count,
          external_calls: external_call_rows,
          today_action_board_ms: service_total("TodayActionBoard"),
          today_action_board_count: service_count("TodayActionBoard"),
          owner_decision_summary_ms: service_total("OwnerDecisionSummary"),
          owner_task_inbox_ms: service_total("OwnerTaskInbox"),
          quality_services_ms: service_total("LearningLoopQualityReport"),
          discovery_services_ms: service_total("DiscoverySourcePerformanceReport"),
          decision_services_ms: service_total("OwnerDecisionSummary"),
          revenue_services_ms: service_total("DashboardSummaryService") + service_total("ActionExpectedValueRanking"),
          operation_status_ms: service_total("operation_status"),
          load_daily_run_execution_status_ms: service_total("load_daily_run_execution_status"),
          load_long_running_operation_monitor_ms: service_total("operation_status"),
          services: service_rows,
          before_actions: duration_rows(@before_actions),
          controller_actions: duration_rows(@controller_actions),
          sql_top_10: sql_top_rows,
          json_generation_ms: nil,
          instrumentation_overhead_ms: round(@instrumentation_overhead_ms),
          runtime: runtime_summary
        }
      end

      def record_duration(collection, name, started, finished)
        row = collection[name.to_s]
        row[:count] += 1
        row[:total_ms] += (finished - started) * 1000
      end

      def total_for(collection)
        collection.values.sum { |row| row[:total_ms] }
      end

      def union_duration_ms(intervals)
        merged = intervals.sort_by(&:first).each_with_object([]) do |(started, finished), result|
          if result.empty? || started > result.last.last
            result << [ started, finished ]
          else
            result.last[1] = [ result.last.last, finished ].max
          end
        end
        merged.sum { |started, finished| (finished - started) * 1000 }
      end

      def duration_rows(collection)
        collection.sort_by { |_name, row| -row[:total_ms] }.to_h do |name, row|
          [ name, { count: row[:count], total_ms: round(row[:total_ms]) } ]
        end
      end

      def service_rows
        duration_rows(@services)
      end

      def service_total(name)
        round(@services[name.to_s][:total_ms])
      end

      def service_count(name)
        @services[name.to_s][:count]
      end

      def sql_top_rows
        @sql_groups.values
          .sort_by { |row| -row[:total_ms] }
          .first(10)
          .map do |row|
            {
              shape: row[:shape],
              caller: row[:caller],
              count: row[:count],
              cached_count: row[:cached_count],
              total_ms: round(row[:total_ms]),
              average_ms: round(row[:total_ms] / row[:count])
            }
          end
      end

      def action_candidate_sql_count
        @sql_groups.values.sum do |row|
          row[:shape].include?('"action_candidates"') ? row[:count] : 0
        end
      end

      def normalize_sql(sql)
        sql
          .gsub(%r{/\*.*?\*/}m, " ")
          .gsub(/'(?:''|[^'])*'/m, "?")
          .gsub(/\$\d+/, "?")
          .gsub(/\b\d+(?:\.\d+)?\b/, "?")
          .squish
          .truncate(SQL_SHAPE_LIMIT)
      end

      def transaction_sql?(sql)
        sql.match?(/\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)
      end

      def record_write(sql)
        case sql.lstrip
        when /\AINSERT\b/i then @insert_count += 1
        when /\AUPDATE\b/i then @update_count += 1
        when /\ADELETE\b/i then @delete_count += 1
        end
      end

      def external_call_rows
        @external_calls.values
          .sort_by { |row| -row[:total_ms] }
          .map do |row|
            row.merge(
              total_ms: round(row[:total_ms]),
              average_ms: round(row[:total_ms] / row[:count])
            )
          end
      end

      def external_category(http)
        host = http.respond_to?(:address) ? http.address.to_s.downcase : ""
        return "github" if host.include?("github")
        return "google" if host.include?("google")
        return "cloudflare" if host.include?("cloudflare")
        return "render" if host.include?("render")

        "other"
      end

      def safe_timeout(http, method_name)
        http.public_send(method_name)
      rescue StandardError
        nil
      end

      def app_caller
        root = defined?(Rails) && Rails.respond_to?(:root) ? Rails.root.to_s : nil
        location = caller_locations(3, CALLER_LIMIT).find do |item|
          root && item.absolute_path.to_s.start_with?("#{root}/app/")
        end
        return unless location

        "#{location.absolute_path.delete_prefix("#{root}/")}:#{location.lineno}"
      end

      def response_bytes(headers, body)
        content_length = headers["content-length"] || headers["Content-Length"]
        return content_length.to_i if content_length.present?

        content = body.respond_to?(:body) ? body.body : nil
        return content.bytesize if content.is_a?(String)
        return content.sum { |part| part.to_s.bytesize } if content.is_a?(Array)
        return body.sum { |part| part.to_s.bytesize } if body.is_a?(Array)

        nil
      rescue StandardError
        nil
      end

      def residual_response_build_ms(process_action_ms:, before_action_ms:, controller_ms:, view_ms:)
        return if process_action_ms.nil?

        [
          process_action_ms.to_f - before_action_ms - controller_ms - view_ms.to_f,
          0.0
        ].max
      end

      def request_id
        @env["action_dispatch.request_id"].presence || @env["HTTP_X_REQUEST_ID"].presence
      end

      def proxy_queue_ms
        raw = @env["HTTP_X_REQUEST_START"].presence || @env["HTTP_X_QUEUE_START"].presence
        return if raw.blank?

        value = raw.to_s.sub(/\At=/, "").to_f
        started_ms =
          if value > 1_000_000_000_000_000
            value / 1000
          elsif value > 1_000_000_000_000
            value
          else
            value * 1000
          end
        queue_ms = (@started_at.to_f * 1000) - started_ms
        queue_ms.negative? ? nil : round(queue_ms)
      rescue StandardError
        nil
      end

      def gc_snapshot
        GC.stat.slice(:time, :count, :major_gc_count, :minor_gc_count, :total_allocated_objects)
      rescue StandardError
        {}
      end

      def gc_delta(finished, key)
        return unless @gc_started.key?(key) && finished.key?(key)

        finished[key] - @gc_started[key]
      end

      def thread_cpu
        clock = if Process.const_defined?(:CLOCK_THREAD_CPUTIME_ID)
          Process::CLOCK_THREAD_CPUTIME_ID
        else
          Process::CLOCK_PROCESS_CPUTIME_ID
        end
        Process.clock_gettime(clock)
      rescue StandardError
        nil
      end

      def ruby_cpu_ms
        return if @cpu_started.nil? || @cpu_finished.nil?

        round((@cpu_finished - @cpu_started) * 1000)
      end

      def current_rss_mb
        return unless File.exist?("/proc/self/status")

        line = File.foreach("/proc/self/status").find { |item| item.start_with?("VmRSS:") }
        kb_to_mb(line)
      rescue StandardError
        nil
      end

      def current_swap_mb
        return unless File.exist?("/proc/self/status")

        line = File.foreach("/proc/self/status").find { |item| item.start_with?("VmSwap:") }
        kb_to_mb(line)
      rescue StandardError
        nil
      end

      def kb_to_mb(line)
        value = line.to_s[/\d+/]&.to_i
        value ? round(value.to_f / 1024) : nil
      end

      def rss_delta_mb
        return if @rss_started_mb.nil? || @rss_finished_mb.nil?

        round(@rss_finished_mb - @rss_started_mb)
      end

      def runtime_summary
        {
          pid: Process.pid,
          web_concurrency: integer_env("WEB_CONCURRENCY"),
          rails_max_threads: integer_env("RAILS_MAX_THREADS") || 3,
          db_pool: db_pool_summary,
          puma: puma_summary
        }
      end

      def integer_env(name)
        value = ENV[name].presence
        value&.to_i
      end

      def db_pool_summary
        return unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection_pool.stat.slice(
          :size,
          :connections,
          :busy,
          :dead,
          :idle,
          :waiting,
          :checkout_timeout
        )
      rescue StandardError
        nil
      end

      def puma_summary
        return unless defined?(Puma) && Puma.respond_to?(:stats)

        raw = JSON.parse(Puma.stats.to_s)
        raw.slice(
          "started_at",
          "backlog",
          "running",
          "pool_capacity",
          "max_threads",
          "requests_count",
          "busy_threads"
        )
      rescue StandardError
        nil
      end

      def measure_instrumentation_overhead
        started = monotonic
        yield
      ensure
        @instrumentation_overhead_ms += elapsed_ms(started) if started
      end

      def finished_elapsed_ms
        finish = @finished_monotonic || monotonic
        (finish - started_monotonic) * 1000
      end

      def elapsed_ms(started)
        (monotonic - started) * 1000
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def numeric_or_nil(value)
        value.nil? ? nil : value.to_f
      end

      def round_or_nil(value)
        value.nil? ? nil : round(value)
      end

      def round(value)
        value.to_f.round(2)
      end
    end

    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Aicoo::SystemModePerformance.target_request?(env)

        tracker = Tracker.new(env)
        result = nil

        Aicoo::SystemModePerformance.with_tracker(tracker) do
          result = @app.call(env)
        end

        status, headers, body = result
        tracker.finish!(status:, headers:, body:)
        timing = tracker.server_timing
        headers["server-timing"] = [ headers["server-timing"], timing ].compact_blank.join(", ")
        tracker.log!
        result
      rescue Exception # rubocop:disable Lint/RescueException
        tracker&.finish!(status: 500, headers: {}, body: nil)
        tracker&.log!
        raise
      end
    end
  end
end
