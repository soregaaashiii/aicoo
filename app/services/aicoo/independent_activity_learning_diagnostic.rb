module Aicoo
  class IndependentActivityLearningDiagnostic
    Row = Data.define(
      :group_key,
      :business_id,
      :area,
      :station,
      :genre,
      :smoking_type,
      :activity_type,
      :shop_count,
      :article_count,
      :created_count,
      :updated_count,
      :learning_status,
      :confidence,
      :roi,
      :outcome,
      :evaluations
    )
    Summary = Data.define(:activity_count, :group_count, :pending_count, :evaluated_count, :skipped_count)
    Result = Data.define(:rows, :summary)

    def initialize(business_id: nil, limit: 1_000)
      @business_id = business_id.presence
      @limit = limit.to_i.positive? ? limit.to_i : 1_000
    end

    def call
      independent = evaluations.filter_map { |evaluation| independent_attributes(evaluation) }
      rows = independent.group_by { |item| item[:attributes]["group_key"] }.values.map { |items| row_for(items) }
      rows.sort_by! { |row| [ -row.confidence.to_f, -(row.roi || -Float::INFINITY).to_f, row.activity_type.to_s ] }
      Result.new(rows:, summary: summary_for(independent, rows))
    end

    private

    attr_reader :business_id, :limit

    def evaluations
      scope = ActivityEvaluation.includes(:business_activity_log).order(id: :desc)
      scope = scope.where(business_id:) if business_id
      scope.limit(limit)
    end

    def independent_attributes(evaluation)
      return unless ActivityLearningTrack.call(evaluation).name == "independent_activity"

      attributes = evaluation.metadata.to_h["independent_activity_learning"].presence ||
        IndependentActivityLearning.new(evaluation).attributes
      return unless attributes["representative_activity_log_id"].to_i == evaluation.business_activity_log_id

      { evaluation:, attributes: }
    end

    def row_for(items)
      latest = items.max_by { |item| [ item[:evaluation].evaluation_window_days, item[:evaluation].id ] }
      attributes = latest[:attributes]
      windows = items.to_h do |item|
        evaluation = item[:evaluation]
        [
          evaluation.evaluation_window_days,
          {
            "status" => evaluation.status,
            "evaluated_at" => evaluation.evaluated_at&.iso8601,
            "metrics" => evaluation.metric_deltas
          }
        ]
      end
      Row.new(
        group_key: attributes["group_key"],
        business_id: attributes["business_id"],
        area: attributes["area"],
        station: attributes["station"],
        genre: attributes["genre"],
        smoking_type: attributes["smoking_type"],
        activity_type: attributes["activity_type"],
        shop_count: attributes["shop_count"],
        article_count: attributes["article_count"],
        created_count: attributes["created_count"],
        updated_count: attributes["updated_count"],
        learning_status: learning_status(windows),
        confidence: attributes["confidence"],
        roi: attributes["roi"],
        outcome: latest_evaluated_outcome(items),
        evaluations: windows
      )
    end

    def latest_evaluated_outcome(items)
      item = items
        .select { |entry| entry[:evaluation].evaluated? }
        .max_by { |entry| [ entry[:evaluation].evaluation_window_days, entry[:evaluation].id ] }
      item&.dig(:attributes, "outcome", "metrics") || {}
    end

    def learning_status(windows)
      statuses = windows.values.map { |value| value["status"] }
      return "evaluated" if statuses.include?("evaluated")
      return "pending" if statuses.include?("pending")

      "skipped"
    end

    def summary_for(items, rows)
      statuses = items.map { |item| item[:evaluation].status }
      Summary.new(
        activity_count: items.map { |item| item[:evaluation].business_activity_log_id }.uniq.size,
        group_count: rows.size,
        pending_count: statuses.count("pending"),
        evaluated_count: statuses.count("evaluated"),
        skipped_count: statuses.count("skipped")
      )
    end
  end
end
