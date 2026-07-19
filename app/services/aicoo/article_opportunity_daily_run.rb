module Aicoo
  class ArticleOpportunityDailyRun
    STEP_NAME = "article_opportunity_analysis".freeze
    MODEL_NAME = ArticleOpportunityAnalyzer::SnapshotRunner::MODEL_NAME
    TERMINAL_STATUSES = %w[rejected rejected_duplicate rejected_irrelevant superseded done invalid resolved].freeze

    Result = Data.define(
      :status,
      :business,
      :snapshot_result,
      :analyzer_result,
      :candidate_created_count,
      :candidate_updated_count,
      :candidate_skipped_count,
      :proposal_promoted_count,
      :duplicate_suppressed_count,
      :today_eligible_count,
      :error_count,
      :warning_count,
      :latest_snapshot_at,
      :latest_candidate_id,
      :errors
    )

    CandidateSummary = Data.define(:created_count, :updated_count, :skipped_count, :candidate_ids)

    def self.target_businesses
      Business.real_businesses.select { |business| target_business?(business) }
    end

    def self.target_business?(business)
      return false unless business
      return true if Aicoo::Suelog::SiteInsightsAdapter.target?(business)

      metadata = business.metadata.to_h
      [
        business.try(:project_key),
        business.try(:repository_name),
        business.try(:local_project_path),
        business.try(:source),
        metadata["source_app"],
        metadata["source_system"],
        metadata["business_key"],
        metadata["slug"],
        metadata["project_key"]
      ].compact.any? { |value| value.to_s.match?(/suelog|sue-log/i) } ||
        business.id.to_i == 2
    end

    def self.call(...)
      new(...).call
    end

    def initialize(daily_run:, business:, limit: nil)
      @daily_run = daily_run
      @business = business
      @limit = limit&.to_i
      @errors = []
    end

    def call
      return skipped_result("business_not_target") unless self.class.target_business?(business)

      snapshot_result = build_snapshots
      return skipped_result("snapshot_empty", snapshot_result:) if snapshot_result.snapshot_count.to_i.zero?

      analyzer_result = analyze_snapshots(snapshot_result.snapshot_ids)
      candidate_summary = persist_candidates(analyzer_result)
      today_result = promote_today_candidates

      status = result_status(snapshot_result:, analyzer_result:, candidate_summary:, today_result:)
      Result.new(
        status:,
        business:,
        snapshot_result:,
        analyzer_result:,
        candidate_created_count: candidate_summary.created_count,
        candidate_updated_count: candidate_summary.updated_count,
        candidate_skipped_count: candidate_summary.skipped_count,
        proposal_promoted_count: today_result.activated_count,
        duplicate_suppressed_count: today_result.duplicate_suppressed_count,
        today_eligible_count: today_result.today_eligible_count,
        error_count: errors.size + snapshot_result.failed_count.to_i + analyzer_result.failed_count.to_i,
        warning_count: warning_count(snapshot_result:, analyzer_result:, candidate_summary:, today_result:),
        latest_snapshot_at: today_result.latest_snapshot_at,
        latest_candidate_id: latest_candidate_id(candidate_summary.candidate_ids),
        errors:
      )
    rescue StandardError => e
      errors << "#{e.class}: #{e.message}"
      Result.new(
        status: "failed",
        business:,
        snapshot_result: nil,
        analyzer_result: nil,
        candidate_created_count: 0,
        candidate_updated_count: 0,
        candidate_skipped_count: 0,
        proposal_promoted_count: 0,
        duplicate_suppressed_count: 0,
        today_eligible_count: 0,
        error_count: errors.size,
        warning_count: 0,
        latest_snapshot_at: nil,
        latest_candidate_id: nil,
        errors:
      )
    end

    def self.metadata_for(result)
      snapshot_result = result.snapshot_result
      analyzer_result = result.analyzer_result
      {
        "business_id" => result.business&.id,
        "started_at" => nil,
        "finished_at" => nil,
        "snapshot_created_count" => snapshot_result&.created_count.to_i,
        "snapshot_skipped_count" => snapshot_skipped_count(snapshot_result),
        "snapshot_updated_count" => snapshot_result&.updated_count.to_i,
        "analyzer_article_count" => analyzer_result&.article_count.to_i,
        "analyzer_success_count" => analyzer_result&.analyzed_count.to_i,
        "analyzer_failed_count" => analyzer_result&.failed_count.to_i,
        "candidate_created_count" => result.candidate_created_count.to_i,
        "candidate_updated_count" => result.candidate_updated_count.to_i,
        "candidate_skipped_count" => result.candidate_skipped_count.to_i,
        "proposal_promoted_count" => result.proposal_promoted_count.to_i,
        "duplicate_suppressed_count" => result.duplicate_suppressed_count.to_i,
        "today_eligible_count" => result.today_eligible_count.to_i,
        "error_count" => result.error_count.to_i,
        "warning_count" => result.warning_count.to_i,
        "latest_snapshot_at" => result.latest_snapshot_at&.iso8601,
        "latest_candidate_id" => result.latest_candidate_id,
        "result_status" => result.status,
        "errors" => result.errors.first(5)
      }.compact
    end

    def self.latest_diagnostic_result(business:)
      step = AicooDailyRunStep
        .where(step_name: STEP_NAME)
        .where("metadata ->> 'business_id' = ?", business.id.to_s)
        .recent
        .first
      run = step&.aicoo_daily_run
      metadata = step&.metadata.to_h
      {
        business:,
        latest_daily_run_id: run&.id,
        latest_step_status: step&.status,
        latest_step_started_at: step&.started_at,
        latest_step_finished_at: step&.finished_at,
        snapshot_created_count: metadata["snapshot_created_count"].to_i,
        analyzer_success_count: metadata["analyzer_success_count"].to_i,
        analyzer_failed_count: metadata["analyzer_failed_count"].to_i,
        candidate_created_count: metadata["candidate_created_count"].to_i,
        proposal_promoted_count: metadata["proposal_promoted_count"].to_i,
        today_eligible_count: metadata["today_eligible_count"].to_i,
        duplicate_suppressed_count: metadata["duplicate_suppressed_count"].to_i,
        latest_snapshot_at: metadata["latest_snapshot_at"],
        latest_candidate_at: latest_candidate_at(metadata["latest_candidate_id"]),
        last_error: step&.error_message.presence || Array(metadata["errors"]).first,
        next_required_action: next_required_action(step, metadata)
      }
    end

    def self.snapshot_skipped_count(snapshot_result)
      return 0 unless snapshot_result

      [
        snapshot_result.published_article_count.to_i -
          snapshot_result.created_count.to_i -
          snapshot_result.updated_count.to_i -
          snapshot_result.failed_count.to_i,
        0
      ].max
    end

    def self.latest_candidate_at(candidate_id)
      return if candidate_id.blank?

      ActionCandidate.where(id: candidate_id).pick(:created_at)
    end

    def self.next_required_action(step, metadata)
      return "Daily Runを実行してください" unless step
      return "エラー内容を確認してください" if step.status == "failed"
      return "ArticleAnalyticsSnapshotの生成条件を確認してください" if metadata["result_status"] == "skipped"
      return "Today候補のstatusと重複抑制を確認してください" if metadata["today_eligible_count"].to_i.zero?

      "対応不要"
    end

    private

    attr_reader :daily_run, :business, :limit, :errors

    def build_snapshots
      ArticleAnalyticsSnapshotBuilder.call(business:, apply: true)
    end

    def analyze_snapshots(snapshot_ids)
      ArticleOpportunityAnalyzer::SnapshotRunner.new(
        business:,
        apply: false,
        limit:,
        snapshot_ids:
      ).call
    end

    def persist_candidates(analyzer_result)
      created = 0
      updated = 0
      skipped = 0
      ids = []

      analyzer_result.article_results.each do |article_result|
        article_result.candidate_drafts.each do |draft|
          existing = existing_candidate_for(draft)
          if existing&.status.to_s.in?(TERMINAL_STATUSES) || existing&.executed?
            skipped += 1
            next
          end

          attributes = candidate_attributes(draft)
          if existing
            existing.update!(attributes)
            updated += 1
            ids << existing.id
          else
            candidate = business.action_candidates.create!(attributes)
            created += 1
            ids << candidate.id
          end
        rescue StandardError => e
          skipped += 1
          errors << "#{e.class}: #{e.message}"
        end
      end

      CandidateSummary.new(created, updated, skipped, ids)
    end

    def existing_candidate_for(draft)
      metadata = draft.metadata.to_h
      business.action_candidates
        .where("metadata ->> 'value_model_name' = ?", MODEL_NAME)
        .where("metadata ->> 'snapshot_id' = ?", metadata["snapshot_id"].to_s)
        .where("metadata ->> 'opportunity_type' = ?", metadata["opportunity_type"].to_s)
        .where(
          "metadata ->> 'article_id' = :article_id OR metadata ->> 'article_path' = :article_path",
          article_id: metadata["article_id"].to_s,
          article_path: metadata["article_path"].to_s
        )
        .order(created_at: :desc, id: :desc)
        .first
    end

    def candidate_attributes(draft)
      metadata = draft.metadata.to_h.merge(
        "daily_run_id" => daily_run&.id,
        "daily_run_step" => STEP_NAME,
        "production_candidate" => true,
        "today_connected" => false,
        "codex_connected" => false
      )
      {
        title: draft.title,
        action_type: draft.action_type,
        status: "archived",
        generation_source: "business_analyzer",
        department: "general",
        immediate_value_yen: 0,
        expected_profit_yen: 0,
        expected_revenue_value_yen: 0,
        expected_total_value_yen: 0,
        final_expected_value_yen: 0,
        success_probability: 0,
        description: draft.description,
        execution_prompt: draft.execution_prompt,
        metadata:
      }
    end

    def promote_today_candidates
      ArticleOpportunityTodayConnector.new(business:, apply: true, limit:).call
    end

    def result_status(snapshot_result:, analyzer_result:, candidate_summary:, today_result:)
      return "failed" if snapshot_result.failed_count.to_i >= snapshot_result.published_article_count.to_i && snapshot_result.published_article_count.to_i.positive?
      return "failed" if analyzer_result.failed_count.to_i.positive? && analyzer_result.analyzed_count.to_i.zero?
      return "warning" if warning_count(snapshot_result:, analyzer_result:, candidate_summary:, today_result:).positive?

      "success"
    end

    def warning_count(snapshot_result:, analyzer_result:, candidate_summary:, today_result:)
      [
        snapshot_result.failed_count.to_i,
        analyzer_result.failed_count.to_i,
        candidate_summary.skipped_count.to_i,
        today_result.duplicate_suppressed_count.to_i,
        today_result.today_eligible_count.to_i.zero? ? 1 : 0,
        unavailable_snapshot_count(snapshot_result)
      ].sum
    end

    def unavailable_snapshot_count(snapshot_result)
      snapshot_result.unavailable_counts.to_h.values.sum(&:to_i)
    end

    def latest_candidate_id(ids)
      ids.compact.max
    end

    def skipped_result(reason, snapshot_result: nil)
      errors << reason
      Result.new(
        status: "skipped",
        business:,
        snapshot_result:,
        analyzer_result: nil,
        candidate_created_count: 0,
        candidate_updated_count: 0,
        candidate_skipped_count: 0,
        proposal_promoted_count: 0,
        duplicate_suppressed_count: 0,
        today_eligible_count: 0,
        error_count: 0,
        warning_count: 1,
        latest_snapshot_at: nil,
        latest_candidate_id: nil,
        errors:
      )
    end
  end
end
