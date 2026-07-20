require "json"
require "net/http"
require "securerandom"

module Aicoo
  module Lovable
    class McpClient
      class Error < StandardError; end

      def initialize(configuration: Configuration.new, transport: nil)
        @configuration = configuration
        @transport = transport
        @request_id = 0
      end

      attr_reader :configuration

      def configured?
        configuration.configured?
      end

      def probe
        call_tool("get_me", {})
      end

      def workspace_id
        return configuration.workspace_id if configuration.workspace_id.present?

        payload = call_tool("list_workspaces", {})
        first_present(payload, %w[workspace_id id]) ||
          raise(Error, "Lovable workspaceを取得できませんでした。LOVABLE_WORKSPACE_IDを設定してください。")
      end

      def create_project(description:, initial_message:)
        call_tool(
          "create_project",
          {
            workspace_id: workspace_id,
            description: description,
            initial_message: initial_message,
            tech_stack: "vite",
            visibility: "private"
          }
        )
      end

      def get_project(project_id:)
        call_tool("get_project", { project_id: })
      end

      def send_message(project_id:, message:)
        call_tool("send_message", { project_id:, message:, wait: true, plan_mode: false })
      end

      def get_diff(project_id:, message_id:)
        return {} if message_id.blank?

        call_tool("get_diff", { project_id:, message_id: })
      end

      def call_tool(name, arguments)
        raise Error, "Lovable MCP OAuth tokenが未設定です。" unless configured?

        initialize_session! unless @initialized
        response = request({
          "method" => "tools/call",
          "params" => { "name" => name, "arguments" => arguments.deep_stringify_keys },
          "id" => next_request_id
        })
        result = response.fetch("result", {})
        if result["isError"]
          raise Error, tool_error_message(name, result)
        end

        normalize_tool_result(result)
      end

      private

      def initialize_session!
        response = request({
          "method" => "initialize",
          "params" => {
            "protocolVersion" => "2025-03-26",
            "capabilities" => {},
            "clientInfo" => { "name" => "aicoo", "version" => "1.0" }
          },
          "id" => next_request_id
        })
        raise Error, "Lovable MCP initializeに失敗しました。" if response["result"].blank?

        request({ "method" => "notifications/initialized", "params" => {} }, notification: true)
        @initialized = true
      end

      def request(payload, notification: false)
        body = { "jsonrpc" => "2.0" }.merge(payload)
        return @transport.call(body, session_id: @session_id, notification:) if @transport

        uri = URI(configuration.mcp_url)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json, text/event-stream"
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{configuration.access_token}"
        request["Mcp-Session-Id"] = @session_id if @session_id.present?
        request.body = JSON.generate(body)

        response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: configuration.open_timeout,
          read_timeout: configuration.read_timeout
        ) { |http| http.request(request) }
        @session_id ||= response["Mcp-Session-Id"].presence

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Lovable MCP HTTP #{response.code}: #{safe_response_body(response.body)}"
        end
        return {} if notification || response.body.blank?

        parsed = parse_response(response.body)
        raise Error, parsed.dig("error", "message").presence || "Lovable MCP requestに失敗しました。" if parsed["error"]

        parsed
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
        raise Error, "Lovable MCPへ接続できませんでした: #{e.message}"
      end

      def parse_response(body)
        return JSON.parse(body) unless body.lstrip.start_with?("event:", "data:")

        data_lines = body.lines.filter_map do |line|
          line.delete_prefix("data:").strip if line.start_with?("data:")
        end
        data_lines.reverse_each do |line|
          next if line.blank? || line == "[DONE]"

          return JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        raise Error, "Lovable MCPのレスポンスを解析できませんでした。"
      rescue JSON::ParserError => e
        raise Error, "Lovable MCPのJSONを解析できませんでした: #{e.message}"
      end

      def normalize_tool_result(result)
        structured = result["structuredContent"]
        return structured.deep_stringify_keys if structured.is_a?(Hash)

        text = Array(result["content"]).filter_map { |item| item["text"] if item["type"] == "text" }.join("\n")
        return result.deep_stringify_keys if text.blank?

        JSON.parse(text)
      rescue JSON::ParserError
        { "text" => text, "content" => result["content"] }
      end

      def first_present(value, keys)
        case value
        when Hash
          keys.each { |key| return value[key] if value[key].present? }
          value.each_value do |child|
            found = first_present(child, keys)
            return found if found.present?
          end
        when Array
          value.each do |child|
            found = first_present(child, keys)
            return found if found.present?
          end
        end
        nil
      end

      def tool_error_message(name, result)
        message = Array(result["content"]).filter_map { |item| item["text"] }.join(" ").presence
        "Lovable #{name}に失敗しました: #{message || 'unknown error'}"
      end

      def safe_response_body(body)
        body.to_s.gsub(/Bearer\s+\S+/i, "Bearer [FILTERED]").first(500)
      end

      def next_request_id
        @request_id += 1
      end
    end
  end
end
