namespace :aicoo do
  desc "Normalize ActionCandidate execution readiness. Use APPLY=1 to update existing unsafe Codex candidates."
  task cleanup_action_candidate_execution_readiness: :environment do
    apply = ENV["APPLY"].to_s.in?(%w[1 true TRUE])
    stats = Hash.new(0)
    candidate_ids = []

    ActionCandidate.active_for_ranking.find_each do |candidate|
      stats[:checked] += 1
      result = Aicoo::ActionCandidateExecutionReadiness.call(candidate)
      metadata = candidate.metadata.to_h.deep_stringify_keys

      if already_cleaned_execution_readiness?(candidate, result)
        stats[:skipped_already_cleaned] += 1
        next
      end

      next if result.ready?
      next unless unsafe_codex_candidate?(candidate, metadata)

      stats[:converted_to_data_preparation] += 1
      candidate_ids << candidate.id
      next unless apply

      candidate.update!(
        action_type: "data_preparation",
        metadata: metadata.merge(result.metadata).merge(
          "execution_readiness_cleanup" => {
            "from_action_type" => candidate.action_type,
            "to_action_type" => "data_preparation",
            "reason" => "not_ready_for_codex",
            "processed_at" => Time.current.iso8601
          }
        )
      )
    rescue StandardError => e
      stats[:failed] += 1
      Rails.logger.warn("[aicoo:cleanup_action_candidate_execution_readiness] action_candidate_id=#{candidate&.id} failed: #{e.class}: #{e.message}")
    end

    puts "mode=#{apply ? 'apply' : 'dry_run'}"
    puts "checked=#{stats[:checked]}"
    puts "converted_to_data_preparation=#{stats[:converted_to_data_preparation]}"
    puts "skipped_already_cleaned=#{stats[:skipped_already_cleaned]}"
    puts "failed=#{stats[:failed]}"
    puts "candidate_ids=#{candidate_ids.join(',')}"
  end

  def unsafe_codex_candidate?(candidate, metadata)
    candidate.code_revision_execution_mode? &&
      (
        metadata["codex_eligible"] == true ||
        metadata["codex_eligible"].to_s == "true" ||
        metadata["auto_revision"] == true ||
        metadata["auto_revision"].to_s == "true" ||
        metadata["auto_merge"] == true ||
        metadata["auto_merge"].to_s == "true" ||
        metadata["auto_deploy"] == true ||
        metadata["auto_deploy"].to_s == "true" ||
        candidate.execution_prompt.present?
      )
  end

  def already_cleaned_execution_readiness?(candidate, result)
    metadata = candidate.metadata.to_h.deep_stringify_keys
    candidate.action_type == "data_preparation" &&
      metadata["codex_eligible"] == false &&
      metadata["auto_revision"] == false &&
      metadata["auto_merge"] == false &&
      metadata["auto_deploy"] == false &&
      metadata["execution_readiness"].to_s == result.readiness.to_s &&
      metadata.dig("execution_readiness_cleanup", "reason").to_s == "not_ready_for_codex"
  end
end
