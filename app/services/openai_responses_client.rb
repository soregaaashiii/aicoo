require "net/http"
require "json"

class OpenaiResponsesClient
  API_ENDPOINT = URI("https://api.openai.com/v1/responses")
  DEFAULT_MODEL = "gpt-5.5"

  class Error < StandardError; end
  class MissingApiKeyError < Error; end

  attr_reader :model

  def initialize(api_key: ENV["OPENAI_API_KEY"], model: ENV.fetch("OPENAI_MODEL", DEFAULT_MODEL))
    @api_key = api_key
    @model = model
  end

  def create_json(prompt:, schema_name:, schema:)
    raise MissingApiKeyError, "OPENAI_API_KEY is not set." if @api_key.blank?

    response = Net::HTTP.start(API_ENDPOINT.host, API_ENDPOINT.port, use_ssl: true) do |http|
      http.request(build_request(prompt:, schema_name:, schema:))
    end

    raise Error, "OpenAI API error: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    raw_response = response.body
    response_json = JSON.parse(raw_response)
    output_text = extract_output_text(response_json)

    { parsed: JSON.parse(output_text), raw_response:, model: }
  rescue JSON::ParserError => e
    raise Error, "OpenAI API response could not be parsed as JSON: #{e.message}"
  end

  private

  def build_request(prompt:, schema_name:, schema:)
    request = Net::HTTP::Post.new(API_ENDPOINT)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      {
        model:,
        input: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        text: {
          format: {
            type: "json_schema",
            name: schema_name,
            strict: true,
            schema:
          }
        }
      }
    )
    request
  end

  def system_prompt
    <<~PROMPT
      You are an AI COO and strategic planning analyst.
      Return only valid JSON that matches the provided schema.
      Estimate conservatively and explain the decision support reasoning.
    PROMPT
  end

  def extract_output_text(response_json)
    return response_json["output_text"] if response_json["output_text"].present?

    response_json.fetch("output").each do |output|
      output.fetch("content", []).each do |content|
        return content["text"] if content["text"].present?
      end
    end

    raise Error, "OpenAI API response did not include output text."
  end
end
