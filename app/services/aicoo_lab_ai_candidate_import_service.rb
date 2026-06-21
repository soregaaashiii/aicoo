class AicooLabAiCandidateImportService
  Result = Data.define(:created_candidates, :skipped_titles, :generation_run)

  def initialize(prompt:, response:)
    @prompt = prompt
    @response = response
  end

  def call
    generation_run = create_generation_run!("running")
    import_result = AicooLabAiCandidatePayloadImporter.new(payload: parsed_response).call

    generation_run.update!(
      status: "succeeded",
      generated_count: import_result.created_candidates.size,
      finished_at: Time.current,
      metadata: generation_metadata(import_result.skipped_titles)
    )

    Result.new(
      created_candidates: import_result.created_candidates,
      skipped_titles: import_result.skipped_titles,
      generation_run:
    )
  rescue StandardError => e
    generation_run&.update!(status: "failed", error_message: e.message, finished_at: Time.current)
    raise
  end

  private

  attr_reader :prompt, :response

  def create_generation_run!(status)
    AicooLabGenerationRun.create!(
      generation_type: "candidate_generation",
      prompt:,
      response:,
      status:,
      started_at: Time.current,
      metadata: { importer: self.class.name, source: "ai_paste" }
    )
  end

  def parsed_response
    JSON.parse(response)
  rescue JSON::ParserError => e
    raise ArgumentError, "Invalid JSON: #{e.message}"
  end

  def generation_metadata(skipped_titles)
    {
      importer: self.class.name,
      source: "ai_paste",
      skipped_duplicate_titles: skipped_titles,
      duplicate_count: skipped_titles.size
    }
  end
end
