module Aicoo
  class ActionCandidateInstructionStabilizer
    def self.call(...)
      new(...).call
    end

    def initialize(action_candidate)
      @action_candidate = action_candidate
    end

    def call
      brief = Aicoo::ActionCandidateExecutionBrief.new(action_candidate)
      snapshot = build_snapshot(brief)
      action_candidate.update_columns(
        execution_prompt: action_candidate.code_revision_execution_mode? ? brief.prompt_markdown : nil,
        metadata: action_candidate.metadata.to_h.merge("execution_instruction" => snapshot),
        updated_at: Time.current
      )
      snapshot
    end

    private

    attr_reader :action_candidate

    def build_snapshot(brief)
      {
        "version" => 1,
        "generated_at" => Time.current.iso8601,
        "target" => brief.target,
        "search_query" => brief.search_query,
        "page_change_type" => brief.page_change_type,
        "expected_effects" => brief.expected_effects,
        "article_plan" => brief.article_plan,
        "file_changes" => brief.file_changes,
        "completion_criteria" => brief.completion_criteria,
        "before_after_items" => brief.before_after_items,
        "quality" => quality_for(brief)
      }
    end

    def quality_for(brief)
      target = brief.target
      before_after_items = brief.before_after_items
      {
        "target_resolved" => target[:url].present? && target[:url] != "未特定",
        "has_candidate_pages" => Array(target[:candidate_pages]).any?,
        "has_before_after" => before_after_items.any? { |row| row[:after].present? && row[:after] != "変更不要" },
        "has_file_changes" => brief.file_changes.any?,
        "has_completion_criteria" => brief.completion_criteria.any?,
        "codex_ready" => codex_ready?(brief),
        "missing_items" => missing_items_for(brief)
      }
    end

    def codex_ready?(brief)
      brief.file_changes.any? &&
        brief.completion_criteria.any? &&
        brief.before_after_items.any? { |row| row[:after].present? && row[:after] != "変更不要" }
    end

    def missing_items_for(brief)
      target = brief.target
      [].tap do |items|
        items << "target_url_or_candidate_pages" if target[:url] == "未特定" && Array(target[:candidate_pages]).blank?
        items << "before_after" unless brief.before_after_items.any? { |row| row[:after].present? && row[:after] != "変更不要" }
        items << "file_changes" if brief.file_changes.blank?
        items << "completion_criteria" if brief.completion_criteria.blank?
      end
    end
  end
end
