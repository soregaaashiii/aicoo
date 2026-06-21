class AicooLabAiCandidatePromptBuilder
  def call
    setting = AicooLabSetting.current

    <<~PROMPT
      You are an AI COO for AICOO Lab.
      Generate experiment candidates that can become teacher data for improving AICOO prediction accuracy.

      Current Lab settings:
      - monthly_budget_yen: #{setting.monthly_budget_yen}
      - minimum_sample_pv: #{setting.minimum_sample_pv}
      - hourly_cost_yen: #{setting.hourly_cost_yen}
      - auto_generate_enabled: #{setting.auto_generate_enabled}
      - free_experiments_continue_after_budget: #{setting.free_experiments_continue_after_budget}

      Candidate generation rules:
      - Prefer low-cost experiments that can be executed quickly.
      - Monthly budget is small, so budget_yen should usually be 0 to 500.
      - estimated_work_minutes should usually be 15 to 120.
      - Generate candidates at the action/experiment level, not at the business category level.
      - Make the target_user, problem_statement, hypothesis, validation_method, expected_learning, and rejection_condition concrete.
      - Include neglect_loss_90d_yen when delaying or ignoring the experiment would likely lose revenue in the next 90 days.
      - Prefer experiments that can be judged by PV, CTA clicks, signup rate, and 90 day learning.
      - Avoid vague ideas that cannot be measured.

      Allowed experiment_type values:
      #{AicooLabExperiment::EXPERIMENT_TYPES.join(", ")}

      Allowed acquisition_channel values:
      #{AicooLabExperiment::ACQUISITION_CHANNELS.join(", ")}

      Return only valid JSON in this exact shape:
      {
        "candidates": [
          {
            "title": "string",
            "description": "string",
            "experiment_type": "lp",
            "market_category": "string",
            "acquisition_channel": "seo",
            "expected_90d_profit_yen": 50000,
            "success_probability": 0.25,
            "budget_yen": 0,
            "estimated_work_minutes": 60,
            "assumed_price_yen": 9800,
            "neglect_loss_90d_yen": 0,
            "neglect_loss_reason": "string",
            "rationale": "string",
            "target_user": "string",
            "problem_statement": "string",
            "hypothesis": "string",
            "validation_method": "string",
            "expected_learning": "string",
            "rejection_condition": "string"
          }
        ]
      }
    PROMPT
  end
end
