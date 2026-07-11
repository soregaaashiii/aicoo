module Aicoo
  module Serp
    class NewBusinessDiscoveryBackfiller
      Result = Data.define(
        :serp_runs_checked,
        :serp_analyses_checked,
        :serp_results_checked,
        :new_business_candidates_created,
        :businesses_created,
        :duplicates_skipped,
        :blank_query_skipped,
        :no_result_skipped,
        :failed,
        :candidate_ids,
        :business_ids,
        :errors
      ) do
        def to_h
          {
            serp_runs_checked:,
            serp_analyses_checked:,
            serp_results_checked:,
            new_business_candidates_created:,
            businesses_created:,
            duplicates_skipped:,
            blank_query_skipped:,
            no_result_skipped:,
            failed:,
            candidate_ids:,
            business_ids:,
            errors:
          }
        end
      end

      def self.call(...)
        new(...).call
      end

      def initialize(scope: nil, limit_per_run: 50)
        @scope = scope
        @limit_per_run = limit_per_run.to_i.positive? ? limit_per_run : 50
      end

      def call
        counters = Hash.new(0)
        candidate_ids = []
        business_ids = []
        errors = []

        serp_runs.find_each do |serp_run|
          counters[:serp_runs_checked] += 1
          result = Aicoo::Serp::NewBusinessDiscoveryGenerator.new(
            serp_run:,
            limit: limit_per_run,
            backfill: true
          ).call

          counters[:serp_analyses_checked] += result.serp_analyses_checked.to_i
          counters[:serp_results_checked] += result.serp_results_checked.to_i
          counters[:new_business_candidates_created] += result.created_count.to_i
          counters[:duplicates_skipped] += result.duplicate_count.to_i
          counters[:blank_query_skipped] += result.blank_query_count.to_i
          counters[:no_result_skipped] += result.no_result_count.to_i
          counters[:failed] += result.failed_count.to_i
          candidate_ids.concat(result.candidates.map(&:id))
          business_ids.concat(result.candidates.filter_map(&:business_id))
          errors.concat(result.errors)

          annotate_serp_run!(serp_run, result)
        rescue StandardError => e
          counters[:failed] += 1
          errors << {
            "serp_run_id" => serp_run.id,
            "error_class" => e.class.name,
            "error_message" => e.message
          }
        end

        Result.new(
          serp_runs_checked: counters[:serp_runs_checked],
          serp_analyses_checked: counters[:serp_analyses_checked],
          serp_results_checked: counters[:serp_results_checked],
          new_business_candidates_created: counters[:new_business_candidates_created],
          businesses_created: created_business_count(candidate_ids),
          duplicates_skipped: counters[:duplicates_skipped],
          blank_query_skipped: counters[:blank_query_skipped],
          no_result_skipped: counters[:no_result_skipped],
          failed: counters[:failed],
          candidate_ids: candidate_ids.uniq,
          business_ids: business_ids.uniq,
          errors: errors.first(20)
        )
      end

      private

      attr_reader :scope, :limit_per_run

      def serp_runs
        (scope || SerpRun.where(status: %w[success partial_failed]))
          .includes(serp_analyses: [ :business, :serp_results ])
          .recent
      end

      def created_business_count(candidate_ids)
        return 0 if candidate_ids.blank?

        ActionCandidate.where(id: candidate_ids).select do |candidate|
          candidate.metadata.to_h.dig("business_promotion", "created_business") == true
        end.size
      end

      def annotate_serp_run!(serp_run, result)
        previous = serp_run.metadata.to_h["new_business_discovery_backfill"].to_h
        serp_run.update_columns(
          metadata: serp_run.metadata.to_h.merge(
            "new_business_discovery_backfill" => previous.merge(
              "last_run_at" => Time.current.iso8601,
              "new_business_candidate_count" => result.created_count,
              "business_ids" => result.candidates.filter_map(&:business_id),
              "candidate_ids" => result.candidates.map(&:id),
              "duplicate_count" => result.duplicate_count,
              "blank_query_count" => result.blank_query_count,
              "no_result_count" => result.no_result_count,
              "failed_count" => result.failed_count
            )
          ),
          updated_at: Time.current
        )
      end
    end
  end
end
