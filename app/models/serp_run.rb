class SerpRun < ApplicationRecord
  STATUSES = %w[running success partial_failed failed].freeze
  EXECUTED_BY = %w[manual scheduler].freeze

  has_many :serp_analyses, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :executed_by, inclusion: { in: EXECUTED_BY }
  validates :query_count, :success_count, :failure_count, :candidate_count, :credit_estimate,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(started_at: :desc, created_at: :desc) }
  scope :today, -> { where(started_at: Time.zone.today.all_day) }

  def running?
    status == "running"
  end

  def successful?
    status == "success"
  end

  def duration_seconds
    return nil unless started_at && finished_at

    (finished_at - started_at).round(2)
  end

  def plan_rows
    metadata.to_h.dig("plan", "rows").to_a
  end

  def skipped_plan_rows
    plan_rows.reject { |row| row["status"] == "run" }
  end

  def run_plan_rows
    plan_rows.select { |row| row["status"] == "run" }
  end

  def action_candidate_count_for_query(query)
    ActionCandidate
      .where(generation_source: %w[serp integrated_decision])
      .where("metadata ->> 'source_query' = ? OR metadata ->> 'serp_keyword' = ?", query, query)
      .count
  end

  def finish_from_result!(result)
    final_status =
      if result.failed_count.to_i.zero?
        "success"
      elsif result.success_count.to_i.positive?
        "partial_failed"
      else
        "failed"
      end

    update!(
      status: final_status,
      finished_at: result.finished_at || Time.current,
      query_count: result.query_count.to_i,
      success_count: result.success_count.to_i,
      failure_count: result.failed_count.to_i,
      candidate_count: candidate_count_for(result),
      credit_estimate: result.estimated_cost_yen.to_i,
      error_message: first_error_message(result),
      metadata: metadata.to_h.merge(
        "provider" => result.provider,
        "target_business_count" => result.target_business_count,
        "result_count" => result.result_count,
        "duration_seconds" => result.duration_seconds,
        "limit" => result.limit,
        "scan_batch_id" => result.scan_batch_id
      )
    )
  end

  def fail!(error)
    update!(
      status: "failed",
      finished_at: Time.current,
      error_message: "#{error.class}: #{error.message}",
      metadata: metadata.to_h.merge("error_class" => error.class.name)
    )
  end

  private

  def candidate_count_for(result)
    queries = result.analyses.map(&:keyword).compact
    ActionCandidate.where(generation_source: "serp")
                   .where(created_at: started_at..Time.current)
                   .where("metadata ->> 'source_query' IN (?) OR metadata ->> 'serp_keyword' IN (?)", queries, queries)
                   .count
  end

  def first_error_message(result)
    result.analyses.find { |analysis| analysis.status == "failed" }&.error_message
  end
end
