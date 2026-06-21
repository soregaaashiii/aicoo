class AicooLabAiDraftImporter
  Result = Data.define(:created_candidates, :skipped_titles)

  def initialize(ai_draft)
    @ai_draft = ai_draft
  end

  def call
    raise ArgumentError, "AI draft must be approved before import" unless ai_draft.importable?

    import_result = AicooLabAiCandidatePayloadImporter.new(payload: ai_draft.parsed_json).call
    ai_draft.transaction do
      ai_draft.generation_run.update!(
        generated_count: import_result.created_candidates.size,
        metadata: ai_draft.generation_run.metadata.merge(
          "importer" => self.class.name,
          "skipped_duplicate_titles" => import_result.skipped_titles,
          "duplicate_count" => import_result.skipped_titles.size
        )
      )
      ai_draft.mark_imported!
    end

    Result.new(
      created_candidates: import_result.created_candidates,
      skipped_titles: import_result.skipped_titles
    )
  end

  private

  attr_reader :ai_draft
end
