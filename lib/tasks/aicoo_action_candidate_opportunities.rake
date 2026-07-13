namespace :aicoo do
  desc "Diagnose ActionCandidate to Opportunity links"
  task diagnose_action_candidate_opportunities: :environment do
    stats = diagnose_action_candidate_opportunities(apply: false)
    print_action_candidate_opportunity_stats(stats)
  end

  desc "Repair safe ActionCandidate to Opportunity links. Set APPLY=1 to persist."
  task repair_action_candidate_opportunities: :environment do
    apply = ENV["APPLY"].to_s == "1"
    stats = diagnose_action_candidate_opportunities(apply:)
    print_action_candidate_opportunity_stats(stats.merge("mode" => apply ? "apply" : "dry-run"))
  end

  def diagnose_action_candidate_opportunities(apply:)
    stats = Hash.new(0)
    stats["candidate_ids"] = []
    stats["unresolved_candidate_ids"] = []

    ActionCandidate.active_for_ranking.includes(:business).find_each do |candidate|
      stats["checked"] += 1
      metadata = candidate.metadata.to_h
      opportunity_id = metadata["opportunity_id"]

      if opportunity_id.present? && OpportunityDiscoveryItem.exists?(id: opportunity_id)
        stats["linked"] += 1
        next
      elsif opportunity_id.present?
        stats["invalid_opportunity"] += 1
      else
        stats["missing_opportunity"] += 1
      end

      if ambiguous_opportunity_candidate?(candidate)
        stats["multiple_possible_opportunities"] += 1
        stats["unresolved_candidate_ids"] << candidate.id
        next
      end

      stats["candidate_ids"] << candidate.id
      if apply
        Aicoo::OpportunityLinker.call(candidate)
        stats["repaired"] += 1
      else
        stats["repairable"] += 1
      end
    rescue StandardError => e
      stats["failed"] += 1
      stats["failed_candidate_ids"] ||= []
      stats["failed_candidate_ids"] << "#{candidate.id}:#{e.class}:#{e.message}"
    end

    stats
  end

  def ambiguous_opportunity_candidate?(candidate)
    metadata = candidate.metadata.to_h
    source_key = metadata["opportunity_key"].presence ||
                 metadata.dig("opportunity", "key").presence ||
                 metadata["source_query"].presence ||
                 metadata["target_keyword"].presence
    return true if source_key.blank? && metadata["metric_rule"].blank? && metadata["issue_key"].blank?

    opportunity_type = metadata["opportunity_type"].presence ||
                       metadata.dig("opportunity", "opportunity_type").presence ||
                       candidate.action_type
    scope = OpportunityDiscoveryItem.where(business_id: candidate.business_id, opportunity_type:)
    return false if scope.count <= 1

    matches = scope.where("metadata ->> 'source_key' = ?", source_key).count
    matches > 1
  end

  def print_action_candidate_opportunity_stats(stats)
    %w[
      mode
      checked
      linked
      missing_opportunity
      multiple_possible_opportunities
      invalid_opportunity
      repairable
      repaired
      failed
    ].each do |key|
      puts "#{key}=#{stats[key] || 0}"
    end
    puts "candidate_ids=#{Array(stats['candidate_ids']).join(',')}"
    puts "unresolved=#{Array(stats['unresolved_candidate_ids']).join(',')}"
    puts "failed_candidate_ids=#{Array(stats['failed_candidate_ids']).join(',')}"
  end
end
