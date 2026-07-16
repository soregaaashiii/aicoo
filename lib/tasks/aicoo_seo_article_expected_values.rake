namespace :aicoo do
  desc "Recalculate SEO article ActionCandidate expected values from incremental clicks only"
  task recalculate_seo_article_expected_values: :environment do
    apply = ENV["APPLY"].to_s == "1"
    scope = ActionCandidate.where(action_type: Aicoo::SeoArticleExpectedValue::ARTICLE_ACTION_TYPES)

    checked = 0
    recalculated = 0
    unchanged = 0
    previously_capped = 0
    cap_removed = 0
    insufficient_data = 0
    failed = 0
    before_total_yen = 0
    after_total_yen = 0
    candidate_ids = []

    puts "mode=#{apply ? 'apply' : 'dry-run'}"

    scope.find_each do |candidate|
      checked += 1
      before_value = candidate.final_expected_value_yen.to_i
      before_total_yen += before_value

      result = Aicoo::SeoArticleExpectedValue.call(candidate)
      after_value = result.final_expected_value_yen.to_i
      after_total_yen += after_value
      capped_before = AicooSeoArticleExpectedValueRake.previously_capped?(candidate)
      previously_capped += 1 if capped_before
      insufficient_data += 1 if result.metadata["calculation_status"].to_s == "insufficient_data"

      if AicooSeoArticleExpectedValueRake.current?(candidate, result)
        unchanged += 1
        next
      end

      recalculated += 1
      cap_removed += 1 if capped_before
      candidate_ids << candidate.id
      puts "candidate_id=#{candidate.id} before=#{before_value} after=#{after_value} raw=#{result.raw_expected_value_yen} status=#{result.metadata['calculation_status']} previously_capped=#{capped_before}"

      next unless apply

      expected_hours = candidate.expected_hours.to_d
      cost_yen = candidate.cost_yen.to_i
      expected_hourly_value_yen = expected_hours.positive? ? (after_value.to_d / expected_hours).round : nil
      roi = cost_yen.positive? ? (after_value.to_d / cost_yen) : nil
      metadata = result.metadata.merge(
        "seo_article_value_recalculated_at" => Time.current.iso8601,
        "seo_article_value_recalculation_before" => {
          "immediate_value_yen" => candidate.immediate_value_yen.to_i,
          "expected_profit_yen" => candidate.expected_profit_yen.to_i,
          "expected_revenue_value_yen" => candidate.expected_revenue_value_yen.to_i,
          "expected_total_value_yen" => candidate.expected_total_value_yen.to_i,
          "final_expected_value_yen" => before_value
        }
      )

      candidate.update_columns(
        immediate_value_yen: after_value,
        expected_profit_yen: after_value,
        expected_revenue_value_yen: after_value,
        expected_total_value_yen: after_value,
        final_expected_value_yen: after_value,
        expected_hourly_value_yen:,
        roi:,
        metadata:,
        updated_at: Time.current
      )
    rescue StandardError => e
      failed += 1
      candidate_ids << candidate.id if defined?(candidate) && candidate&.id
      warn "candidate_id=#{candidate&.id || 'unknown'} failed=#{e.class}: #{e.message}"
    end

    puts "checked=#{checked}"
    puts "recalculated=#{recalculated}"
    puts "unchanged=#{unchanged}"
    puts "previously_capped=#{previously_capped}"
    puts "cap_removed=#{cap_removed}"
    puts "insufficient_data=#{insufficient_data}"
    puts "failed=#{failed}"
    puts "before_total_yen=#{before_total_yen}"
    puts "after_total_yen=#{after_total_yen}"
    puts "delta_yen=#{after_total_yen - before_total_yen}"
    puts "candidate_ids=#{candidate_ids.uniq.join(',')}"
  end
end

module AicooSeoArticleExpectedValueRake
  def self.current?(candidate, result)
    metadata = candidate.metadata.to_h
    metadata.dig("seo_article_value_model", "calculation_version").to_s == Aicoo::SeoArticleExpectedValue::CALCULATION_VERSION &&
      candidate.expected_profit_yen.to_i == result.final_expected_value_yen.to_i &&
      candidate.expected_revenue_value_yen.to_i == result.final_expected_value_yen.to_i &&
      candidate.expected_total_value_yen.to_i == result.final_expected_value_yen.to_i &&
      candidate.final_expected_value_yen.to_i == result.final_expected_value_yen.to_i
  end

  def self.previously_capped?(candidate)
    metadata = candidate.metadata.to_h
    metadata["seo_expected_value_cap"].present? ||
      metadata["seo_expected_value_cap_yen"].present? ||
      metadata["cap_applied"].to_s == "true" ||
      metadata["cap_reason"].present? ||
      metadata.dig("seo_article_value_model", "cap_yen").present? ||
      metadata.dig("seo_article_value_model", "cap_applied").to_s == "true"
  end
end
