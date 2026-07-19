module Aicoo
  class ArticleOpportunityAnalyzer
    class SnapshotComparator
      ARTICLE_ACTION_TYPES = %w[article_create article_update new_article_candidate seo_article smoking_info_verify].freeze
      LEGACY_VALUE_MODEL_NAMES = %w[article_opportunity_analyzer suelog_article theme_learning_v2].freeze

      Result = Data.define(
        :mode,
        :business,
        :legacy_article_count,
        :new_article_count,
        :legacy_action_candidate_count,
        :new_action_candidate_count,
        :created_count,
        :failed_count,
        :match_count,
        :match_rate,
        :rank_differences,
        :article_results,
        :candidate_ids
      )

      def initialize(business:, apply: false, limit: nil)
        @business = business
        @apply = ActiveModel::Type::Boolean.new.cast(apply)
        @limit = limit
      end

      def call
        new_result = ArticleOpportunityAnalyzer.from_snapshots(business:, apply:, limit:)
        legacy_rows = legacy_candidates
        rank_differences = compare_rankings(legacy_rows, new_result.article_results)
        matches = rank_differences.count { |row| row["legacy_rank"].present? && row["new_rank"].present? }

        Result.new(
          mode: apply ? "apply" : "dry-run",
          business:,
          legacy_article_count: legacy_rows.map { |candidate| article_key_for_candidate(candidate) }.compact_blank.uniq.size,
          new_article_count: new_result.article_count,
          legacy_action_candidate_count: legacy_rows.size,
          new_action_candidate_count: new_result.action_candidate_count,
          created_count: new_result.created_count,
          failed_count: new_result.failed_count,
          match_count: matches,
          match_rate: new_result.article_count.positive? ? ((matches.to_d / new_result.article_count) * 100).round(1).to_f : 0.0,
          rank_differences:,
          article_results: new_result.article_results,
          candidate_ids: new_result.candidate_ids
        )
      end

      private

      attr_reader :business, :apply, :limit

      def legacy_candidates
        @legacy_candidates ||= business.action_candidates
          .where(action_type: ARTICLE_ACTION_TYPES)
          .where.not(status: ActionCandidate::INACTIVE_STATUSES)
          .select { |candidate| legacy_article_candidate?(candidate) }
          .sort_by { |candidate| -candidate.final_expected_value_yen.to_i }
      end

      def legacy_article_candidate?(candidate)
        metadata = candidate.metadata.to_h.deep_stringify_keys
        value_model_name = metadata["value_model_name"].presence || metadata.dig("value_model", "name")
        return true if value_model_name.to_s.in?(LEGACY_VALUE_MODEL_NAMES)
        return true if metadata["analysis_source"].to_s.in?(%w[suelog_db business_analyzer])
        return true if metadata["source_query"].present? || metadata["planned_url"].present? || metadata["target_url"].present?

        false
      end

      def compare_rankings(legacy_rows, article_results)
        legacy_by_key = legacy_rows.each_with_index.each_with_object({}) do |(candidate, index), hash|
          key = article_key_for_candidate(candidate)
          hash[key] ||= { candidate:, rank: index + 1 } if key.present?
        end
        new_by_key = article_results.sort_by { |result| [ -result.expected_improvement_score.to_d, -result.opportunity_score.to_d ] }.each_with_index.each_with_object({}) do |(result, index), hash|
          hash[result.normalized_path] = { result:, rank: index + 1 } if result.normalized_path.present?
        end

        (legacy_by_key.keys + new_by_key.keys).compact_blank.uniq.map do |key|
          legacy = legacy_by_key[key]
          current = new_by_key[key]
          {
            "article_key" => key,
            "legacy_candidate_id" => legacy&.dig(:candidate)&.id,
            "legacy_title" => legacy&.dig(:candidate)&.title,
            "legacy_rank" => legacy&.dig(:rank),
            "legacy_expected_value_yen" => legacy&.dig(:candidate)&.final_expected_value_yen.to_i,
            "new_snapshot_id" => current&.dig(:result)&.snapshot_id,
            "new_article_id" => current&.dig(:result)&.article_id,
            "new_title" => current&.dig(:result)&.title,
            "new_rank" => current&.dig(:rank),
            "new_opportunity_score" => current&.dig(:result)&.opportunity_score,
            "new_expected_improvement_score" => current&.dig(:result)&.expected_improvement_score,
            "rank_delta" => rank_delta(legacy&.dig(:rank), current&.dig(:rank)),
            "new_opportunities" => Array(current&.dig(:result)&.opportunities).map { |row| row["opportunity_type"] }
          }
        end.sort_by { |row| [ row["new_rank"] || 999_999, row["legacy_rank"] || 999_999 ] }
      end

      def article_key_for_candidate(candidate)
        metadata = candidate.metadata.to_h.deep_stringify_keys
        [
          metadata["article_path"],
          metadata["normalized_path"],
          metadata["target_url"],
          metadata["planned_url"],
          metadata["proposed_url"],
          metadata["value_model"].is_a?(Hash) ? metadata.dig("value_model", "article_path") : nil
        ].compact_blank.map { |value| Aicoo::UrlNormalizer.call(value) }.find(&:present?)
      end

      def rank_delta(legacy_rank, new_rank)
        return nil unless legacy_rank && new_rank

        new_rank - legacy_rank
      end
    end
  end
end
