module Aicoo
  module Serp
    class PriorityUpdater
      Result = Data.define(:updated_count, :suggested_count, :inactive_candidate_count, :skipped_count)

      def self.update_all!
        updated_count = 0
        suggested_count = 0
        inactive_candidate_count = 0
        skipped_count = 0

        Business.real_businesses.includes(:business_serp_keywords).find_each do |business|
          suggested_count += Aicoo::Serp::KeywordManager.generate_suggestions!(business:).size

          business.business_serp_keywords.where(status: %w[active paused]).find_each do |keyword|
            if manual_priority?(keyword)
              skipped_count += 1
              next
            end

            new_score = score_for(keyword)
            inactive_reasons = inactive_reasons_for(keyword)
            keyword.update!(
              priority_score: new_score,
              opportunity_score: new_score,
              metadata_json: keyword.metadata_json.to_h.merge(
                "priority_updated_at" => Time.current.iso8601,
                "priority_source" => "serp_learning",
                "inactive_candidate" => inactive_reasons.any?,
                "inactive_reasons" => inactive_reasons
              )
            )
            updated_count += 1
            inactive_candidate_count += 1 if inactive_reasons.any?
          end
        end

        Result.new(updated_count:, suggested_count:, inactive_candidate_count:, skipped_count:)
      end

      def self.manual_priority?(keyword)
        keyword.metadata_json.to_h["manual_priority"] == true
      end

      def self.inactive_reasons_for(keyword)
        reasons = []
        reasons << "30日取得なし" if keyword.last_checked_at.blank? || keyword.last_checked_at < 30.days.ago
        reasons << "検索流入0" if keyword.latest_clicks.to_i.zero? && keyword.latest_impressions.to_i.zero? && keyword.check_count.to_i.positive?
        reasons << "順位変化なし" if stable_rank?(keyword)
        reasons << "90日成果なし" if no_recent_success?(keyword)
        reasons
      end

      def self.score_for(keyword)
        score = keyword.priority_score.to_i
        score += 12 if keyword.latest_clicks.to_i.positive?
        score += 8 if keyword.latest_impressions.to_i >= 100
        score += 8 if keyword.latest_rank.to_i.positive? && keyword.latest_rank.to_i <= 10
        score += 6 if candidate_adopted?(keyword)
        score -= 12 if inactive_reasons_for(keyword).any?
        score.clamp(0, 100)
      end

      def self.stable_rank?(keyword)
        latest_rank = keyword.latest_rank.to_i
        return false if latest_rank.zero?

        previous_rank = keyword.metadata_json.to_h["previous_latest_rank"].to_i
        previous_rank.positive? && previous_rank == latest_rank && keyword.check_count.to_i >= 3
      end

      def self.no_recent_success?(keyword)
        return false unless keyword.updated_at < 90.days.ago

        keyword.latest_clicks.to_i.zero? && keyword.latest_impressions.to_i.zero?
      end

      def self.candidate_adopted?(keyword)
        keyword.business.action_candidates
               .where(generation_source: "serp")
               .where("metadata ->> 'serp_keyword' = ?", keyword.keyword)
               .where(status: %w[approved executor_queued in_progress done])
               .exists?
      end
    end
  end
end
