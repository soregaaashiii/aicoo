class AicooLabAiDraftCreator
  Result = Data.define(:ai_draft, :generation_run)

  def initialize(title:, prompt:, raw_response:)
    @title = title
    @prompt = prompt
    @raw_response = raw_response
  end

  def call
    parsed_json = parse_response
    generation_run = AicooLabGenerationRun.create!(
      generation_type: "candidate_generation",
      prompt:,
      response: raw_response,
      status: "succeeded",
      generated_count: candidate_count(parsed_json),
      started_at: Time.current,
      finished_at: Time.current,
      metadata: { source: "ai_draft", creator: self.class.name }
    )
    ai_draft = AicooLabAiDraft.create!(
      title:,
      generation_run:,
      raw_response:,
      parsed_json:,
      status: "draft"
    )

    Result.new(ai_draft:, generation_run:)
  end

  private

  attr_reader :title, :prompt, :raw_response

  def parse_response
    JSON.parse(raw_response)
  rescue JSON::ParserError => e
    raise ArgumentError, "Invalid JSON: #{e.message}"
  end

  def candidate_count(parsed_json)
    candidates = parsed_json.is_a?(Array) ? parsed_json : parsed_json.fetch("candidates", [])
    candidates.is_a?(Array) ? candidates.size : 0
  end
end
