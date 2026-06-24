module Aicoo
  class ExploreDailyRoutine
    Result = Data.define(
      :generated_at,
      :import_needed,
      :import_message,
      :new_observation_count,
      :high_score_observation_count,
      :opportunity_review_count,
      :high_priority_opportunity_count,
      :top_observation,
      :top_opportunity,
      :recommended_next_step,
      :routine_status
    )
    NextStep = Data.define(:label, :path, :reason)

    def call
      Result.new(
        generated_at: Time.current,
        import_needed: import_needed?,
        import_message: import_message,
        new_observation_count: observation_focus.total_count,
        high_score_observation_count: observation_focus.high_priority_count,
        opportunity_review_count: opportunity_focus.total_count,
        high_priority_opportunity_count: opportunity_focus.high_priority_count,
        top_observation: observation_focus.top_observation,
        top_opportunity: opportunity_focus.top_item&.opportunity,
        recommended_next_step: recommended_next_step,
        routine_status: routine_status
      )
    end

    private

    def import_needed?
      ExploreImportLog.where(created_at: Time.current.all_day).none?
    end

    def import_message
      return "今日はまだExplore Importがありません。" if import_needed?

      "今日のExplore Importは完了しています。"
    end

    def routine_status
      return "overloaded" if overloaded?
      return "import_needed" if import_needed?
      return "review_observations" if observation_focus.total_count.positive?
      return "review_opportunities" if opportunity_focus.total_count.positive?

      "clear"
    end

    def overloaded?
      observation_focus.total_count >= 20 ||
        opportunity_focus.total_count >= 10 ||
        observation_focus.high_priority_count >= 5
    end

    def recommended_next_step
      return next_step("Explore Importへ", routes.admin_explore_import_path, "今日はまだImportがないため、まず外部シグナルを貼り付けてください。") if import_needed?
      return next_step("Observation Focusへ", routes.admin_explore_observations_focus_path, "高score Observationがあります。Opportunity化・却下・保留を判断してください。") if observation_focus.high_priority_count.positive?
      return next_step("Opportunity Focusへ", routes.focus_owner_opportunities_path, "高優先度Opportunityがあります。ActionCandidate化を判断してください。") if opportunity_focus.high_priority_count.positive?
      return next_step("Opportunity Focusへ", routes.focus_owner_opportunities_path, "レビュー待ちOpportunityがあります。") if opportunity_focus.total_count.positive?

      next_step("Exploreは本日分処理済み", routes.owner_focus_path, "今すぐ処理すべきExplore Routineはありません。")
    end

    def next_step(label, path, reason)
      NextStep.new(label:, path:, reason:)
    end

    def observation_focus
      @observation_focus ||= ExploreObservationFocusQueue.new.call
    end

    def opportunity_focus
      @opportunity_focus ||= OpportunityFocusQueue.new.call
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
