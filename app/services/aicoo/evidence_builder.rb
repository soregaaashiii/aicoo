module Aicoo
  class EvidenceBuilder
    EVIDENCE_TYPES = %w[gsc ga4 serp explore revenue decision_log manual system].freeze
    INSUFFICIENT_SCORE = 40.to_d

    Result = Data.define(
      :evidence_score,
      :evidence_summary,
      :evidence_warning,
      :evidence_items,
      :missing_sources,
      :metadata
    )

    def initialize(subject)
      @subject = subject
    end

    def call
      items = evidence_items
      score = evidence_score(items)
      missing_sources = missing_sources_for(items)
      warning = score < INSUFFICIENT_SCORE
      summary = summary_for(items:, score:, warning:)

      Result.new(
        evidence_score: score,
        evidence_summary: summary,
        evidence_warning: warning,
        evidence_items: items,
        missing_sources:,
        metadata: {
          "score" => score.to_s,
          "summary" => summary,
          "warning" => warning,
          "missing_sources" => missing_sources,
          "items" => items
        }
      )
    end

    private

    attr_reader :subject

    def evidence_items
      [
        *evaluator_breakdown_items,
        *explore_items,
        *business_metric_items,
        *serp_items,
        *revenue_items,
        decision_log_item,
        source_item
      ].compact.first(8)
    end

    def evaluator_breakdown_items
      Array(subject_metadata["evaluator_breakdown"]).filter_map do |entry|
        entry = entry.to_h
        evaluator_type = entry["evaluator_type"] || entry[:evaluator_type]
        next unless evaluator_type.present?

        source = evaluator_type.to_s.downcase
        next unless EVIDENCE_TYPES.include?(source) || %w[learning judge].include?(source)

        snapshot(
          source: source == "learning" ? "system" : source,
          title: "#{evaluator_type.to_s.upcase}評価",
          summary: entry["reason"].presence || "#{evaluator_type} evaluatorの評価結果です。",
          metric_name: "expected_value_yen",
          current_value: entry["expected_value_yen"] || entry[:expected_value_yen],
          importance_score: entry["confidence_score"] || entry[:confidence_score],
          confidence: entry["confidence_score"] || entry[:confidence_score],
          captured_at: Time.current
        )
      end
    end

    def explore_items
      observations = []
      observations << subject.source_observation if subject.respond_to?(:source_observation) && subject.source_observation
      if subject.respond_to?(:opportunity_discovery_items)
        observations.concat(subject.opportunity_discovery_items.includes(:source_observation).filter_map(&:source_observation))
      end
      observations.uniq.filter_map do |observation|
        data_source = observation.explore_data_source
        snapshot(
          source: "explore",
          title: observation.title,
          summary: observation.description.presence || "#{data_source.source_type}からのExplore signalです。",
          metric_name: observation.observation_type,
          current_value: observation.score,
          importance_score: observation.score,
          confidence: observation.score,
          url: observation.metadata.to_h["url"],
          page: observation.metadata.to_h["page"],
          keyword: observation.metadata.to_h["keyword"],
          captured_at: observation.observed_at || observation.created_at
        )
      end
    end

    def business_metric_items
      return [] unless business

      metrics = BusinessMetricDaily.where(business:).order(recorded_on: :desc).limit(2).to_a
      return [] if metrics.empty?

      latest = metrics.first
      previous = metrics.second
      [
        metric_snapshot(
          source: "gsc",
          title: "検索流入指標",
          metric_name: "impressions",
          current_value: latest.impressions,
          baseline_value: previous&.impressions,
          captured_at: latest.recorded_on
        ),
        metric_snapshot(
          source: "ga4",
          title: "サイト行動指標",
          metric_name: "sessions",
          current_value: latest.sessions,
          baseline_value: previous&.sessions,
          captured_at: latest.recorded_on
        )
      ].compact.select { |item| item["current_value"].to_d.positive? }
    end

    def serp_items
      return [] unless business

      analysis = SerpAnalysis.where(business:).order(analyzed_at: :desc).first
      return [] unless analysis

      [
        snapshot(
          source: "serp",
          title: "SERP競合状況",
          summary: "#{analysis.keyword} の競合状況を確認済みです。",
          metric_name: "competition_score",
          current_value: analysis.competition_score,
          importance_score: analysis.competition_score,
          confidence: 60,
          keyword: analysis.keyword,
          captured_at: analysis.analyzed_at
        )
      ]
    end

    def revenue_items
      return [] unless business

      amount = RevenueEvent.where(business:, event_type: "revenue", occurred_on: 30.days.ago.to_date..Date.current).sum(:amount)
      return [] unless amount.positive?

      [
        snapshot(
          source: "revenue",
          title: "直近30日の売上記録",
          summary: "直近30日の売上記録があります。",
          metric_name: "revenue_30d",
          current_value: amount,
          importance_score: 65,
          confidence: 70,
          captured_at: Time.current
        )
      ]
    end

    def decision_log_item
      action_type = value_for(:action_type)
      return unless action_type.present?

      scope = OwnerDecisionLog.last_30_days.where(action_type:)
      total = scope.count
      return if total.zero?

      positive = scope.where(decision_type: OwnerDecisionLog::POSITIVE_DECISIONS).count
      rate = (positive.to_d / total * 100).round(1)
      snapshot(
        source: "decision_log",
        title: "類似提案のOwner判断",
        summary: "類似action_typeの採用系判断率は#{rate}%です。",
        metric_name: "positive_decision_rate",
        current_value: rate,
        baseline_value: 50,
        importance_score: [ rate, 90 ].min,
        confidence: [ total * 10, 80 ].min,
        captured_at: Time.current
      )
    end

    def source_item
      source = if subject.is_a?(OpportunityDiscoveryItem)
        subject.source_type
      elsif subject.respond_to?(:generation_source)
        subject.generation_source
      end
      return if source.blank?

      evidence_source = source.in?(%w[gsc ga4 serp revenue]) ? source : (source.in?(%w[manual owner_discovery]) ? "manual" : "system")
      snapshot(
        source: evidence_source,
        title: "生成元",
        summary: "#{source} 由来の提案です。",
        metric_name: "generation_source",
        current_value: source,
        importance_score: evidence_source == "manual" ? 20 : 35,
        confidence: evidence_source == "manual" ? 25 : 35,
        captured_at: subject.respond_to?(:created_at) ? subject.created_at : Time.current
      )
    end

    def metric_snapshot(source:, title:, metric_name:, current_value:, baseline_value:, captured_at:)
      change_rate = change_rate_for(current_value, baseline_value)
      direction = change_rate.nil? ? "現在値は#{current_value.to_i}です。" : "前回比#{change_rate}%です。"
      snapshot(
        source:,
        title:,
        summary: "#{metric_name} の#{direction}",
        metric_name:,
        current_value:,
        baseline_value:,
        change_rate:,
        importance_score: importance_from_change(current_value, change_rate),
        confidence: baseline_value.present? ? 70 : 45,
        captured_at:
      )
    end

    def snapshot(source:, title:, summary:, metric_name: nil, current_value: nil, baseline_value: nil, change_rate: nil, importance_score: 50, confidence: 50, url: nil, page: nil, keyword: nil, captured_at: nil)
      {
        "source" => source,
        "title" => title,
        "summary" => summary,
        "metric_name" => metric_name,
        "current_value" => current_value,
        "baseline_value" => baseline_value,
        "change_rate" => change_rate,
        "importance_score" => clamp(importance_score),
        "confidence" => clamp(confidence),
        "url" => url,
        "page" => page,
        "keyword" => keyword,
        "business" => business&.name,
        "captured_at" => captured_at || Time.current
      }.compact
    end

    def evidence_score(items)
      return 0.to_d if items.empty?

      source_count = items.pluck("source").uniq.size
      source_score = [ source_count * 18, 45 ].min
      average_confidence = average(items.pluck("confidence"))
      average_importance = average(items.pluck("importance_score"))
      recency_score = recency_score_for(items)

      (source_score + average_confidence * 0.25 + average_importance * 0.2 + recency_score * 0.1).round(2)
    end

    def recency_score_for(items)
      newest = items.filter_map { |item| parse_time(item["captured_at"]) }.max
      return 20.to_d unless newest
      return 100.to_d if newest >= 7.days.ago
      return 70.to_d if newest >= 30.days.ago
      return 40.to_d if newest >= 90.days.ago

      15.to_d
    end

    def summary_for(items:, score:, warning:)
      return [ "Evidence不足: 判断に使える根拠データがまだありません。" ] if items.empty?

      lines = items.sort_by { |item| -item["importance_score"].to_d }.first(4).map do |item|
        "・#{item['summary']}"
      end
      lines << "・Evidence Scoreが#{score.to_i}のため、根拠不足として扱います。" if warning
      lines
    end

    def missing_sources_for(items)
      present = items.pluck("source")
      %w[gsc ga4 serp explore revenue decision_log].reject { |source| present.include?(source) }
    end

    def change_rate_for(current_value, baseline_value)
      current = current_value.to_d
      baseline = baseline_value.to_d
      return if baseline.zero?

      ((current - baseline) / baseline * 100).round(1)
    end

    def importance_from_change(current_value, change_rate)
      base = current_value.to_d.positive? ? 45 : 20
      base += [ change_rate.to_d.abs, 45 ].min if change_rate
      clamp(base)
    end

    def average(values)
      values = values.compact.map(&:to_d)
      return 0.to_d if values.empty?

      values.sum / values.size
    end

    def subject_metadata
      subject.respond_to?(:metadata) ? subject.metadata.to_h : {}
    end

    def business
      return subject.business if subject.respond_to?(:business) && subject.business

      nil
    end

    def value_for(attribute)
      return subject.public_send(attribute) if subject.respond_to?(attribute)

      subject_metadata[attribute.to_s]
    end

    def parse_time(value)
      return value if value.respond_to?(:to_time)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def clamp(value)
      [ [ value.to_d, 0.to_d ].max, 100.to_d ].min
    end
  end
end
