module Aicoo
  class ActionCandidateDeduplicator
    require "set"

    Result = Data.define(:checked, :duplicates, :merged, :updated, :failed, :candidate_ids)

    class << self
      def call(apply: false)
        new(apply:).call
      end
    end

    def initialize(apply: false)
      @apply = apply
      @checked = 0
      @duplicates = 0
      @merged = 0
      @updated = 0
      @failed = 0
      @candidate_ids = []
      @groups = Hash.new { |hash, key| hash[key] = [] }
    end

    def call
      collect_groups
      duplicate_groups.each { |group| merge_group(group) }

      Result.new(
        checked:,
        duplicates:,
        merged:,
        updated:,
        failed:,
        candidate_ids: candidate_ids.uniq
      )
    end

    private

    attr_reader :apply, :groups
    attr_accessor :checked, :duplicates, :merged, :updated, :failed, :candidate_ids

    def collect_groups
      ActionCandidate.includes(:business).active_for_ranking.find_each do |candidate|
        self.checked += 1
        key = dedupe_key_for(candidate)
        next if key.blank?

        groups[key] << candidate
      rescue StandardError => e
        self.failed += 1
        Rails.logger.warn("[ActionCandidateDeduplicator] collect action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
      end
    end

    def duplicate_groups
      groups.values.select { |candidates| candidates.size > 1 }
    end

    def merge_group(candidates)
      keep = canonical_candidate(candidates)
      duplicate_candidates = candidates.reject { |candidate| candidate.id == keep.id }
      self.duplicates += duplicate_candidates.size
      self.candidate_ids += candidates.map(&:id)
      return unless apply

      ActionCandidate.transaction do
        duplicate_candidates.each { |duplicate| merge_duplicate!(keep, duplicate) }
        mark_canonical!(keep, duplicate_candidates)
      end
    rescue StandardError => e
      self.failed += 1
      Rails.logger.warn("[ActionCandidateDeduplicator] merge ids=#{candidates.map(&:id).join(',')} failed: #{e.class}: #{e.message}")
    end

    def canonical_candidate(candidates)
      candidates.max_by do |candidate|
        [
          candidate.immediate_value_yen.to_i,
          candidate.expected_profit_yen.to_i,
          candidate.final_expected_value_yen.to_i,
          candidate.updated_at || Time.zone.at(0),
          candidate.id
        ]
      end
    end

    def merge_duplicate!(keep, duplicate)
      transfer_related_records!(keep, duplicate)
      duplicate.update_columns(
        status: "archived",
        metadata: duplicate.metadata.to_h.deep_stringify_keys.merge(
          "archived_reason" => "duplicate_action_candidate",
          "duplicate_of_action_candidate_id" => keep.id,
          "deduplicated_at" => Time.current.iso8601
        ),
        updated_at: Time.current
      )
      self.merged += 1
    end

    def transfer_related_records!(keep, duplicate)
      AutoRevisionTask.where(action_candidate_id: duplicate.id).update_all(action_candidate_id: keep.id, updated_at: Time.current)
      CodexPromptDraft.where(action_candidate_id: duplicate.id).update_all(action_candidate_id: keep.id, updated_at: Time.current)
      ActionExecutionLog.where(action_candidate_id: duplicate.id).update_all(action_candidate_id: keep.id, updated_at: Time.current)
      OpportunityDiscoveryItem.where(action_candidate_id: duplicate.id).update_all(action_candidate_id: keep.id, updated_at: Time.current)
      RevenueEvent.where(action_candidate_id: duplicate.id).update_all(action_candidate_id: keep.id, updated_at: Time.current)
      transfer_action_execution!(keep, duplicate)
      transfer_action_result!(keep, duplicate)
      transfer_score_snapshots!(keep, duplicate)
    end

    def transfer_action_execution!(keep, duplicate)
      return if keep.action_execution.present?

      duplicate.action_execution&.update_columns(action_candidate_id: keep.id, updated_at: Time.current)
    end

    def transfer_action_result!(keep, duplicate)
      return if keep.action_result.present?

      duplicate.action_result&.update_columns(action_candidate_id: keep.id, updated_at: Time.current)
    end

    def transfer_score_snapshots!(keep, duplicate)
      existing_dates = keep.action_candidate_score_snapshots.pluck(:recorded_on).to_set
      duplicate.action_candidate_score_snapshots.find_each do |snapshot|
        unless existing_dates.include?(snapshot.recorded_on)
          snapshot.update_columns(action_candidate_id: keep.id, updated_at: Time.current)
        end
      end
    end

    def mark_canonical!(keep, duplicates)
      metadata = keep.metadata.to_h.deep_stringify_keys
      existing_ids = Array(metadata["duplicate_candidate_ids"])
      keep.update_columns(
        metadata: metadata.merge(
          "dedupe_key" => dedupe_key_for(keep),
          "duplicate_candidate_ids" => (existing_ids + duplicates.map(&:id)).uniq,
          "dedupe_repair_applied_at" => Time.current.iso8601
        ),
        updated_at: Time.current
      )
      self.updated += 1
    end

    def dedupe_key_for(candidate)
      key = Aicoo::ActionCandidateUpserter.dedupe_key_for(candidate)
      candidate.update_columns(
        metadata: candidate.metadata.to_h.deep_stringify_keys.merge("dedupe_key" => key),
        updated_at: Time.current
      ) if apply && key.present? && candidate.metadata.to_h["dedupe_key"].blank?
      key
    end
  end
end
