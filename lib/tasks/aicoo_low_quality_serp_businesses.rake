namespace :aicoo do
  desc "Diagnose SERP-derived businesses whose theme quality may need review"
  task diagnose_low_quality_serp_businesses: :environment do
    scope = Business.real_businesses.where(source: "serp").order(:id)
    checked = 0

    puts "business_id,business_name,source_query,target_customer,problem,solution,monetization,validation_plan,quality_status,quality_warnings"

    scope.find_each do |business|
      checked += 1
      metadata = business.metadata.to_h
      candidate = source_candidate_for(business, metadata)
      source = candidate&.metadata.to_h || metadata

      attributes = {
        "business_name" => source["business_name"].presence || business.name,
        "target_customer" => source["target_customer"].presence || source["customer"],
        "problem" => source["problem"],
        "solution" => source["solution"].presence || source["offering"].presence || source["provided_service"],
        "monetization" => source["monetization"].presence || source["revenue_model"],
        "validation_plan" => source["validation_plan"].presence || source["validation_method"].presence || source["validation_step"],
        "product_type" => source["product_type"].presence || source["launch_asset_type"].presence || source["lp_or_saas"]
      }
      quality = Aicoo::Serp::BusinessIdeaQualityJudge.call(
        attributes: attributes,
        source_query: source["source_query"].presence || metadata["source_query"]
      )

      row = [
        business.id,
        business.name,
        source["source_query"].presence || metadata["source_query"],
        attributes["target_customer"],
        attributes["problem"],
        attributes["solution"],
        attributes["monetization"],
        attributes["validation_plan"],
        quality.status,
        quality.reasons.join(" / ")
      ]
      puts row.map { |value| csv_cell(value) }.join(",")
    end

    puts "checked=#{checked}"
  end

  def source_candidate_for(business, metadata)
    candidate_id = metadata["action_candidate_id"].presence ||
                   metadata["source_action_candidate_id"].presence
    return ActionCandidate.find_by(id: candidate_id) if candidate_id

    ActionCandidate
      .where(business_id: business.id, generation_source: "serp", department: "new_business")
      .order(updated_at: :desc)
      .first
  end

  def csv_cell(value)
    text = value.to_s.gsub('"', '""').gsub(/\s+/, " ").strip
    %("#{text}")
  end
end
