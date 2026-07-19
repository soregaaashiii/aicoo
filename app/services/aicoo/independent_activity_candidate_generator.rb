require "digest"

module Aicoo
  class IndependentActivityCandidateGenerator
    GENERATION_SOURCE = "independent_learning".freeze
    MIN_CONFIDENCE = 0.7
    MIN_ROI = 0.0
    MIN_SAMPLE_COUNT = 3
    REQUIRED_WINDOW_DAYS = 7

    Row = Data.define(
      :learning_id,
      :business_id,
      :activity_type,
      :area,
      :station,
      :genre,
      :smoking_type,
      :roi,
      :confidence,
      :sample_count,
      :candidate_generated,
      :candidate_id,
      :duplicate,
      :eligible,
      :skip_reason,
      :generation_reason,
      :strategy_key,
      :action_type,
      :observed_revenue_delta_yen,
      :observed_work_cost_yen,
      :estimated_work_hours
    )
    Summary = Data.define(
      :learning_count,
      :eligible_count,
      :generated_count,
      :duplicate_count,
      :rejected_count,
      :reason_counts
    )
    Result = Data.define(:rows, :summary)

    def self.call(business_id: nil, apply: false, limit: 5_000)
      new(business_id:, apply:, limit:).call
    end

    def initialize(business_id: nil, apply: false, limit: 5_000)
      @business_id = business_id.presence
      @apply = apply
      @limit = limit.to_i.positive? ? limit.to_i : 5_000
    end

    def call
      rows = learning_patterns.map { |samples| evaluate_pattern(samples) }
      rows.sort_by! { |row| [ row.eligible ? 0 : 1, -row.confidence.to_f, -row.roi.to_f, row.strategy_key ] }
      Result.new(rows:, summary: summary_for(rows))
    end

    private

    attr_reader :business_id, :apply, :limit

    def learning_patterns
      diagnostic.rows
        .group_by { |row| pattern_key(row) }
        .values
    end

    def diagnostic
      @diagnostic ||= IndependentActivityLearningDiagnostic.new(business_id:, limit:).call
    end

    def evaluate_pattern(samples)
      seven_day_samples = samples.select { |sample| seven_day_evaluated?(sample) }
      sample_count = seven_day_samples.size
      confidence = seven_day_samples.filter_map { |sample| window_value(sample, "confidence") || sample.confidence }.map(&:to_f).max.to_f
      roi = median(seven_day_samples.filter_map { |sample| window_value(sample, "roi") || sample.roi })
      revenue_delta = median(seven_day_samples.filter_map { |sample| metric_delta(sample, "revenue_yen") })
      work_cost = median(seven_day_samples.filter_map { |sample| window_value(sample, "work_cost_yen") })
      work_seconds = median(seven_day_samples.filter_map { |sample| window_value(sample, "estimated_work_seconds") })
      skip_reason = rejection_reason(samples:, seven_day_samples:, sample_count:, confidence:, roi:, revenue_delta:)
      eligible = skip_reason.nil?
      sample = latest_sample(seven_day_samples.presence || samples)
      strategy_key = strategy_key_for(sample)
      existing = eligible ? duplicate_candidate(sample, strategy_key) : nil
      candidate = existing

      if eligible && existing.nil? && apply
        candidate, duplicate_after_lock = create_or_find_candidate!(
          sample:,
          samples: seven_day_samples,
          strategy_key:,
          roi:,
          confidence:,
          sample_count:,
          revenue_delta:,
          work_cost:,
          work_seconds:
        )
        existing = candidate if duplicate_after_lock
      end

      Row.new(
        learning_id: sample.group_key,
        business_id: sample.business_id,
        activity_type: sample.activity_type,
        area: sample.area,
        station: sample.station,
        genre: sample.genre,
        smoking_type: sample.smoking_type,
        roi:,
        confidence: confidence.round(2),
        sample_count:,
        candidate_generated: candidate.present?,
        candidate_id: candidate&.id,
        duplicate: existing.present?,
        eligible:,
        skip_reason: existing.present? ? "duplicate_active_candidate" : skip_reason,
        generation_reason: generation_reason(sample, roi:, confidence:, sample_count:),
        strategy_key:,
        action_type: action_type_for(sample.activity_type),
        observed_revenue_delta_yen: revenue_delta&.round,
        observed_work_cost_yen: work_cost&.round,
        estimated_work_hours: estimated_work_hours(work_seconds, work_cost)
      )
    end

    def rejection_reason(samples:, seven_day_samples:, sample_count:, confidence:, roi:, revenue_delta:)
      return "seven_day_evaluation_incomplete" if seven_day_samples.empty?
      return "sample_count_below_minimum" if sample_count < MIN_SAMPLE_COUNT
      return "confidence_below_threshold" if confidence < MIN_CONFIDENCE
      return "roi_not_positive" if roi.nil? || roi <= MIN_ROI
      return "positive_revenue_delta_missing" if revenue_delta.nil? || revenue_delta <= 0
      return "business_not_found" unless Business.exists?(id: samples.first.business_id)

      nil
    end

    def create_or_find_candidate!(sample:, samples:, strategy_key:, roi:, confidence:, sample_count:, revenue_delta:, work_cost:, work_seconds:)
      business = Business.find(sample.business_id)
      business.with_lock do
        existing = duplicate_candidate(sample, strategy_key)
        return [ existing, true ] if existing

        attributes = candidate_attributes(
          sample:,
          samples:,
          strategy_key:,
          roi:,
          confidence:,
          sample_count:,
          revenue_delta:,
          work_cost:,
          work_seconds:
        )
        [ business.action_candidates.create!(attributes), false ]
      end
    end

    def candidate_attributes(sample:, samples:, strategy_key:, roi:, confidence:, sample_count:, revenue_delta:, work_cost:, work_seconds:)
      title = title_for(sample)
      action_type = action_type_for(sample.activity_type)
      reason = generation_reason(sample, roi:, confidence:, sample_count:)
      {
        title:,
        description: "Independent Learningより生成。#{reason}",
        evaluation_reason: reason,
        action_type:,
        status: "proposal",
        generation_source: GENERATION_SOURCE,
        department: "general",
        immediate_value_yen: revenue_delta.round,
        cost_yen: work_cost&.round,
        expected_hours: estimated_work_hours(work_seconds, work_cost),
        success_probability: confidence,
        confidence_score: (confidence * 100).round.clamp(0, 100),
        data_confidence_score: (confidence * 100).round.clamp(0, 100),
        metadata: candidate_metadata(
          sample:,
          samples:,
          strategy_key:,
          roi:,
          confidence:,
          sample_count:,
          revenue_delta:,
          work_cost:,
          reason:,
          title:,
          action_type:
        )
      }.compact
    end

    def candidate_metadata(sample:, samples:, strategy_key:, roi:, confidence:, sample_count:, revenue_delta:, work_cost:, reason:, title:, action_type:)
      {
        "generation_source" => GENERATION_SOURCE,
        "execution_mode" => "manual_operation",
        "codex_eligible" => false,
        "auto_revision" => false,
        "auto_merge" => false,
        "auto_deploy" => false,
        "data_sources_used" => [ GENERATION_SOURCE ],
        "area" => sample.area,
        "station" => sample.station,
        "genre" => sample.genre,
        "smoking_type" => sample.smoking_type,
        "concrete_task" => title,
        "recommended_action" => title,
        "independent_learning" => {
          "learning_id" => sample.group_key,
          "learning_ids" => samples.map(&:group_key).uniq,
          "strategy_key" => strategy_key,
          "activity_type" => sample.activity_type,
          "action_type" => action_type,
          "area" => sample.area,
          "station" => sample.station,
          "genre" => sample.genre,
          "smoking_type" => sample.smoking_type,
          "sample_count" => sample_count,
          "roi" => roi.round(3),
          "confidence" => confidence.round(2),
          "evaluation_window_days" => REQUIRED_WINDOW_DAYS,
          "observed_revenue_delta_yen" => revenue_delta.round,
          "observed_work_cost_yen" => work_cost&.round,
          "generation_reason" => reason,
          "thresholds" => {
            "minimum_confidence" => MIN_CONFIDENCE,
            "minimum_roi" => MIN_ROI,
            "minimum_sample_count" => MIN_SAMPLE_COUNT
          },
          "generated_at" => Time.current.iso8601
        },
        "evidence" => {
          "source" => GENERATION_SOURCE,
          "area" => sample.area,
          "genre" => sample.genre,
          "current_value" => roi.round(3),
          "benchmark_value" => MIN_ROI,
          "reason" => reason,
          "expected_effect" => "同じ条件の改善を再現する"
        },
        "action_plan" => {
          "execution_mode" => "manual_operation",
          "goal" => title,
          "summary" => title,
          "target" => target_label(sample),
          "owner_output" => "対象を確認して実施し、完了後に登録件数を入力する"
        }
      }.compact
    end

    def duplicate_candidate(sample, strategy_key)
      scope = ActionCandidate
        .where(business_id: sample.business_id, action_type: action_type_for(sample.activity_type))
        .active_for_ranking
      scope.find do |candidate|
        metadata = candidate.metadata.to_h.deep_stringify_keys
        metadata.dig("independent_learning", "strategy_key") == strategy_key ||
          same_dimensions?(metadata, sample) ||
          normalize(candidate.title) == normalize(title_for(sample))
      end
    end

    def same_dimensions?(metadata, sample)
      dimensions = {
        "area" => sample.area,
        "genre" => sample.genre,
        "smoking_type" => sample.smoking_type
      }
      return false if dimensions.values.all?(&:blank?)

      dimensions.all? do |key, value|
        normalize(metadata[key].presence || metadata.dig("independent_learning", key)) == normalize(value)
      end
    end

    def pattern_key(row)
      [ row.business_id, row.activity_type, row.area, row.station, row.genre, row.smoking_type ].map { |value| normalize(value) }
    end

    def strategy_key_for(row)
      Digest::SHA256.hexdigest([ row.business_id, action_type_for(row.activity_type), row.area, row.genre, row.smoking_type ].map { |value| normalize(value) }.join(":"))
    end

    def seven_day_evaluated?(row)
      row.evaluations.dig(REQUIRED_WINDOW_DAYS, "status") == "evaluated"
    end

    def window_value(row, key)
      row.evaluations.dig(REQUIRED_WINDOW_DAYS, key)
    end

    def metric_delta(row, metric)
      value = row.evaluations.dig(REQUIRED_WINDOW_DAYS, "metrics", metric, "delta")
      value.to_f if value.present?
    end

    def latest_sample(samples)
      samples.max_by do |sample|
        [ sample.evaluations.dig(REQUIRED_WINDOW_DAYS, "evaluated_at").to_s, sample.group_key.to_s ]
      end
    end

    def median(values)
      numbers = values.map(&:to_f).sort
      return if numbers.empty?

      middle = numbers.length / 2
      numbers.length.odd? ? numbers[middle] : (numbers[middle - 1] + numbers[middle]) / 2.0
    end

    def estimated_work_hours(work_seconds, work_cost)
      return (work_seconds.to_f / 3600.0).round(2) if work_seconds.to_f.positive?

      hourly_cost = AicooLabSetting.first&.hourly_cost_yen.to_f
      return if hourly_cost.zero? || work_cost.to_f <= 0

      (work_cost.to_f / hourly_cost).round(2)
    end

    def action_type_for(activity_type)
      type = activity_type.to_s
      return "article_create" if type.match?(/\Aarticle_(?:create|created|add|added)\z/)
      return "seo_improvement" if type.match?(/(?:seo|title)/)
      return "article_update" if type.match?(/(?:article|content|body|internal_link)/)
      return "shop_data_cleanup" unless type.match?(/\Ashop_(?:create|created|add|added)\z/)

      "other"
    end

    def title_for(sample)
      location = sample.area.presence || sample.station.presence || "対象エリア"
      genre = sample.genre.presence || (sample.source_model == "Article" ? "記事" : "店舗")
      smoking = sample.smoking_type.present? ? "#{sample.smoking_type}の" : ""
      type = sample.activity_type.to_s
      return "#{location}の#{smoking}#{genre}を追加する" if type.match?(/\Ashop_(?:create|created|add|added)\z/)
      return "#{location}の#{smoking}#{genre}に関する記事を追加する" if type.match?(/\Aarticle_(?:create|created|add|added)\z/)
      return "#{location}の#{genre}記事のタイトルを改善する" if type.include?("title")
      return "#{location}の#{genre}記事へ内部リンクを追加する" if type.include?("internal_link")
      return "#{location}の#{genre}記事のSEOを改善する" if type.include?("seo")
      return "#{location}の#{genre}記事を改善する" if sample.source_model == "Article"

      "#{location}の#{smoking}#{genre}の店舗情報を改善する"
    end

    def target_label(sample)
      [ sample.area.presence || sample.station.presence, sample.genre, sample.smoking_type ].compact_blank.join(" / ").presence || "対象条件"
    end

    def generation_reason(sample, roi:, confidence:, sample_count:)
      "Independent Learningで#{target_label(sample)}の#{sample.activity_type}が#{sample_count}回再現され、ROI #{roi.to_f.round(2)}・confidence #{confidence.to_f.round(2)}を確認"
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[[:space:]　]+/, " ").strip
    end

    def summary_for(rows)
      rejected = rows.reject(&:eligible)
      Summary.new(
        learning_count: rows.size,
        eligible_count: rows.count(&:eligible),
        generated_count: rows.count { |row| row.candidate_generated && !row.duplicate },
        duplicate_count: rows.count(&:duplicate),
        rejected_count: rejected.size,
        reason_counts: (rejected.map(&:skip_reason) + rows.select(&:duplicate).map(&:skip_reason)).compact.tally
      )
    end
  end
end
