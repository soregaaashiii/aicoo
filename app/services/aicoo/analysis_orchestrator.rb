module Aicoo
  class AnalysisOrchestrator
    SOURCES = %w[gsc ga4 serp x youtube clarity google_ads meta_ads reddit github product_hunt explore].freeze
    Result = Data.define(:generated_at, :candidates, :created_count, :updated_count, :skipped_count)
    PersistResult = Data.define(:candidates, :created_count, :updated_count)
    SourceSignal = Data.define(
      :business,
      :source,
      :expected_value_yen,
      :estimated_cost_yen,
      :estimated_minutes,
      :roi,
      :confidence,
      :priority,
      :execution_mode,
      :reason,
      :evidence,
      :last_run_at
    )

    def self.run_all!(today: Date.current, limit_per_business: nil, collect_records: true)
      candidates = []
      created_count = 0
      updated_count = 0
      skipped_count = 0

      Business.real_businesses.find_each do |business|
        result = new(business:, today:).call(limit: limit_per_business)
        candidates.concat(result.candidates) if collect_records
        created_count += result.created_count
        updated_count += result.updated_count
        skipped_count += result.skipped_count
      end

      Result.new(
        generated_at: Time.current,
        candidates:,
        created_count:,
        updated_count:,
        skipped_count:
      )
    end

    def initialize(business:, today: Date.current, health: nil, cost_engine: nil)
      DataSourceCostProfile.ensure_defaults!
      @business = business
      @today = today.to_date
      @health = health
      @cost_engine = cost_engine || Aicoo::CostEngine.new(business:)
    end

    def call(limit: nil, persist: true)
      all_signals = build_signals.sort_by { |signal| [ -signal.priority.to_d, -signal.roi.to_d ] }
      signals = all_signals
      signals = signals.first(limit) if limit
      persist_result = persist ? persist_signals(signals) : PersistResult.new(candidates: signals, created_count: 0, updated_count: 0)

      Result.new(
        generated_at: Time.current,
        candidates: persist_result.candidates,
        created_count: persist_result.created_count,
        updated_count: persist_result.updated_count,
        skipped_count: [ all_signals.size - signals.size, 0 ].max
      )
    end

    def preview(limit: nil)
      call(limit:, persist: false).candidates
    end

    private

    attr_reader :business, :today, :health, :cost_engine

    def build_signals
      SOURCES.filter_map do |source|
        estimate = cost_engine.estimate(source)
        next unless estimate.enabled && estimate.business_enabled

        expected_value = expected_value_for(source, estimate)
        cost = estimate.estimated_cost_yen
        roi = ratio(expected_value, cost) || estimate.roi || (cost.zero? ? nil : 0.to_d)
        confidence = confidence_for(source, estimate)
        priority = priority_for(source, expected_value:, cost:, roi:, confidence:)
        next if priority <= 0

        SourceSignal.new(
          business:,
          source:,
          expected_value_yen: expected_value.to_i,
          estimated_cost_yen: cost.to_d,
          estimated_minutes: estimated_minutes_for(source, estimate),
          roi:,
          confidence:,
          priority:,
          execution_mode: recommended_execution_mode_for(source, estimate, priority:, roi:),
          reason: reason_for(source, estimate, expected_value:, roi:, priority:),
          evidence: evidence_for(source, estimate),
          last_run_at: last_run_at_for(source, estimate)
        )
      end
    end

    def persist_signals(signals)
      created_count = 0
      updated_count = 0
      candidates = signals.map do |signal|
        candidate = AnalysisCandidate.find_or_initialize_by(
          business: signal.business,
          analysis_source: signal.source,
          due_on: today
        )
        new_record = candidate.new_record?
        candidate.assign_attributes(
          expected_value_yen: signal.expected_value_yen,
          estimated_cost_yen: signal.estimated_cost_yen,
          estimated_minutes: signal.estimated_minutes,
          roi: signal.roi,
          confidence: signal.confidence,
          priority: signal.priority,
          execution_mode: signal.execution_mode,
          reason: signal.reason,
          evidence: signal.evidence,
          last_run_at: signal.last_run_at,
          status: candidate.status.presence || "pending",
          metadata: candidate.metadata.to_h.merge(
            "generated_by" => "Aicoo::AnalysisOrchestrator",
            "cost_engine" => {
              "source_key" => signal.source,
              "estimated_cost_yen" => signal.estimated_cost_yen.to_s,
              "expected_value_yen" => signal.expected_value_yen,
              "roi" => signal.roi&.to_s
            }
          )
        )
        candidate.save!
        new_record ? created_count += 1 : updated_count += 1
        candidate
      end
      PersistResult.new(candidates:, created_count:, updated_count:)
    end

    def expected_value_for(source, estimate)
      base = estimate.expected_profit_yen.to_d
      base += health_warning_bonus(source)
      base += stale_data_bonus(source)
      base += opportunity_gap_bonus(source)
      base += action_gap_bonus
      base += evidence_gap_bonus(source)
      base += playbook_bonus(source)
      [ base, 0 ].max.round
    end

    def priority_for(source, expected_value:, cost:, roi:, confidence:)
      mode_weight = case DataSourceCostProfile.for_source(source).execution_mode
      when "auto" then 1.1
      when "smart" then 1.0
      else 0.85
      end
      cost_penalty = cost.to_d.positive? ? [ cost.to_d / 50, 20 ].min : 0
      roi_score = roi.present? ? [ roi.to_d, 100 ].min : (cost.to_d.zero? ? 30 : 0)
      score = (expected_value.to_d / 100) + (roi_score * 0.4) + (confidence.to_d * 0.25) - cost_penalty
      (score * mode_weight).round(2)
    end

    def confidence_for(source, estimate)
      score = 35.to_d
      score += 25 if estimate.linked?
      score += 15 if last_run_at_for(source, estimate).present?
      score += 10 if business.business_playbook&.learned?
      score -= 10 if estimate.warning.present?
      [ [ score, 0 ].max, 100 ].min
    end

    def recommended_execution_mode_for(source, estimate, priority:, roi:)
      return "manual" if estimate.manual?
      return "auto" if estimate.auto? && estimate.estimated_cost_yen.to_d.zero?
      return "smart" if priority.to_d >= 40 && (roi.blank? || roi.to_d >= 1)

      estimate.execution_mode
    end

    def reason_for(source, estimate, expected_value:, roi:, priority:)
      reasons = []
      reasons << "Business Healthに警告があります" if health_warning_for(source).present?
      reasons << "データ鮮度が落ちています" if stale_source?(source, estimate)
      reasons << "Opportunityが不足しています" if opportunity_gap?
      reasons << "ActionCandidateが不足しています" if action_gap?
      reasons << "Evidence不足を補えます" if evidence_gap_for?(source)
      reasons << "Business Playbook上、この分析の期待値があります" if playbook_bonus(source).positive?
      reasons << "推定ROI #{roi.to_d.round(1)}" if roi.present?
      reasons << "期待値 #{expected_value.to_i}円 / 優先度 #{priority.to_d.round(1)}"
      reasons.join(" / ")
    end

    def evidence_for(source, estimate)
      {
        "source" => source,
        "execution_mode" => estimate.execution_mode,
        "cost_level" => estimate.cost_level,
        "business_linked" => estimate.linked?,
        "connection_status" => estimate.connection_status,
        "health_warning" => health_warning_for(source),
        "opportunity_gap" => opportunity_gap?,
        "action_gap" => action_gap?,
        "stale" => stale_source?(source, estimate),
        "playbook_roi" => analysis_playbook_row(source)&.dig("roi")
      }.compact
    end

    def estimated_minutes_for(source, estimate)
      return 5 if estimate.auto?
      return 15 if estimate.smart?
      return 30 if source.in?(%w[serp x youtube reddit])

      20
    end

    def health_warning_bonus(source)
      health_warning_for(source).present? ? 1_500.to_d : 0.to_d
    end

    def stale_data_bonus(source)
      stale_source?(source, cost_engine.estimate(source)) ? 1_000.to_d : 0.to_d
    end

    def opportunity_gap_bonus(source)
      return 0.to_d unless opportunity_gap?

      source.in?(%w[serp x youtube reddit explore]) ? 1_500.to_d : 500.to_d
    end

    def action_gap_bonus
      action_gap? ? 800.to_d : 0.to_d
    end

    def evidence_gap_bonus(source)
      evidence_gap_for?(source) ? 700.to_d : 0.to_d
    end

    def playbook_bonus(source)
      row = analysis_playbook_row(source)
      return 0.to_d unless row

      [ row["roi"].to_d * 100, 2_000 ].min
    end

    def analysis_playbook_row(source)
      business.business_playbook&.metadata.to_h.dig("analysis_summary", source)
    end

    def health_warning_for(source)
      source_health = health_row&.public_send(source) if health_row && source.in?(%w[gsc ga4 serp explore])
      source_health&.warning
    end

    def stale_source?(source, estimate)
      last = last_run_at_for(source, estimate)
      return true if last.blank? && source.in?(%w[serp x youtube reddit clarity])

      last.present? && last < 7.days.ago
    end

    def last_run_at_for(source, estimate)
      case source
      when "gsc", "ga4"
        source_health = health_row&.public_send(source)
        source_health&.last_fetched_at || estimate.last_run_at
      when "serp"
        business.serp_analyses.maximum(:analyzed_at) || estimate.last_run_at
      when "explore"
        business.opportunity_discovery_items.maximum(:created_at) || estimate.last_run_at
      else
        estimate.last_run_at
      end
    end

    def opportunity_gap?
      business.opportunity_discovery_items.where(created_at: 14.days.ago..).count < 2
    end

    def action_gap?
      business.action_candidates.where(created_at: 14.days.ago..).count < 2
    end

    def evidence_gap_for?(source)
      return true if source.in?(%w[gsc ga4 serp]) && recent_low_evidence_count.positive?

      recent_low_evidence_count >= 3 && source.in?(%w[x youtube reddit clarity])
    end

    def recent_low_evidence_count
      @recent_low_evidence_count ||= business.action_candidates.where(created_at: 30.days.ago..).count do |candidate|
        candidate.metadata.to_h.dig("evidence", "warning") == true ||
          candidate.metadata.to_h.dig("evidence", "score").to_d < Aicoo::EvidenceBuilder::INSUFFICIENT_SCORE
      end
    end

    def health_row
      @health_row ||= health || Aicoo::BusinessIntegrationHealth.new.call.business_healths.find { |row| row.business == business }
    end

    def ratio(numerator, denominator)
      return nil if denominator.to_d.zero?

      numerator.to_d / denominator.to_d
    end
  end
end
