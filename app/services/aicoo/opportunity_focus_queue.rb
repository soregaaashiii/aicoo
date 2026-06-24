module Aicoo
  class OpportunityFocusQueue
    Result = Data.define(:items, :top_item, :total_count, :high_priority_count, :generated_at)
    Item = Data.define(
      :opportunity,
      :focus_score,
      :priority,
      :reason,
      :recommended_action,
      :source_performance_summary
    )

    HIGH_THRESHOLD = 80
    MEDIUM_THRESHOLD = 60

    def call
      Result.new(
        items:,
        top_item: items.first,
        total_count: items.size,
        high_priority_count: items.count { |item| item.priority == "high" },
        generated_at: Time.current
      )
    end

    private

    def items
      @items ||= OpportunityDiscoveryItem.includes(:business)
                                        .where(status: "new")
                                        .map { |opportunity| build_item(opportunity) }
                                        .sort_by { |item| [ -item.focus_score, item.opportunity.discovered_at || item.opportunity.created_at ] }
    end

    def build_item(opportunity)
      score_parts = score_parts_for(opportunity)
      score = score_parts.values.sum

      Item.new(
        opportunity:,
        focus_score: score,
        priority: priority_for(score),
        reason: reason_for(score_parts),
        recommended_action: recommended_action_for(score),
        source_performance_summary: source_summary_for(opportunity.source_type)
      )
    end

    def score_parts_for(opportunity)
      {
        "Opportunity Score" => opportunity.opportunity_score.presence || 50,
        "発見源補正" => source_type_performance_bonus(opportunity.source_type),
        "新着補正" => freshness_bonus(opportunity),
        "事業補正" => business_priority_bonus(opportunity.business),
        "未レビュー経過" => stale_penalty(opportunity)
      }
    end

    def source_type_performance_bonus(source_type)
      return 20 if strongest_source_types.include?(source_type)
      return -10 if weakest_source_types.include?(source_type)

      0
    end

    def freshness_bonus(opportunity)
      discovered_at = opportunity.discovered_at || opportunity.created_at
      return 0 unless discovered_at

      discovered_at >= 7.days.ago ? 10 : 0
    end

    def stale_penalty(opportunity)
      discovered_at = opportunity.discovered_at || opportunity.created_at
      return 0 unless discovered_at

      discovered_at <= 30.days.ago ? -10 : 0
    end

    def business_priority_bonus(business)
      return 0 unless business
      return 10 if business.revenue_events.revenue.exists?

      5
    end

    def priority_for(score)
      return "high" if score >= HIGH_THRESHOLD
      return "medium" if score >= MEDIUM_THRESHOLD

      "low"
    end

    def reason_for(score_parts)
      score_parts.map { |label, value| "#{label}: #{signed_value(value)}" }.join(" / ")
    end

    def recommended_action_for(score)
      return "最優先で内容を確認し、検証できるならActionCandidate化してください。" if score >= HIGH_THRESHOLD
      return "内容を確認し、必要ならReviewedにして候補化タイミングを待ってください。" if score >= MEDIUM_THRESHOLD

      "今すぐ候補化せず、仮説の具体性を確認してください。"
    end

    def signed_value(value)
      numeric = value.to_d
      numeric.positive? ? "+#{numeric.to_i}" : numeric.to_i.to_s
    end

    def strongest_source_types
      @strongest_source_types ||= discovery_report.strongest_sources.map(&:source_type)
    end

    def weakest_source_types
      @weakest_source_types ||= discovery_report.weakest_sources.map(&:source_type)
    end

    def source_summary_for(source_type)
      discovery_report.source_summaries.find { |summary| summary.source_type == source_type }
    end

    def discovery_report
      @discovery_report ||= DiscoverySourcePerformanceReport.new.call
    end
  end
end
