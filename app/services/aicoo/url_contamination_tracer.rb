module Aicoo
  class UrlContaminationTracer
    DEFAULT_TABLES = %w[
      serp_results
      serp_analyses
      serp_queries
      action_candidates
      action_executions
      auto_revision_tasks
      action_candidate_score_snapshots
      action_execution_logs
      auto_revision_executions
      auto_revision_run_logs
      aicoo_daily_runs
      aicoo_daily_run_steps
      codex_prompt_drafts
      codex_submissions
    ].freeze

    Result = Data.define(:environment, :database, :url, :matches, :repairs, :cause, :display_source) do
      def to_h
        {
          environment:,
          database:,
          url:,
          matches:,
          repairs:,
          cause:,
          display_source:
        }
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(url:, fix: false, tables: DEFAULT_TABLES)
      @url = url.to_s
      @fix = ActiveModel::Type::Boolean.new.cast(fix)
      @tables = tables
    end

    def call
      matches = tables.flat_map { |table| search_table(table) }
      repairs = fix ? repair!(matches) : []
      Result.new(
        environment: Rails.env,
        database: ActiveRecord::Base.connection_db_config.database,
        url:,
        matches:,
        repairs:,
        cause: cause_for(matches),
        display_source: display_source_for(matches)
      )
    end

    private

    attr_reader :url, :fix, :tables

    def search_table(table)
      return [] unless connection.data_source_exists?(table)

      columns = searchable_columns(table)
      return [] if columns.empty?

      quoted_table = connection.quote_table_name(table)
      needle = connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(url)}%")
      where_sql = columns.map { |column| "CAST(#{connection.quote_column_name(column.name)} AS text) ILIKE #{needle}" }.join(" OR ")
      rows = connection.exec_query(
        "SELECT * FROM #{quoted_table} WHERE #{where_sql}",
        "url_contamination_trace"
      )
      rows.map { |row| normalize_match(table, row, columns) }
    end

    def searchable_columns(table)
      connection.columns(table).select do |column|
        column.type.in?(%i[string text json jsonb]) || column.sql_type_metadata.sql_type.match?(/json|text|character|varchar/i)
      end
    end

    def normalize_match(table, row, columns)
      matched_columns = columns.filter_map do |column|
        value = row[column.name]
        column.name if value.to_s.include?(url)
      end
      {
        table:,
        id: row["id"],
        business_id: row["business_id"] || business_id_for(table, row),
        action_candidate_id: row["action_candidate_id"],
        serp_analysis_id: row["serp_analysis_id"],
        serp_run_id: row["serp_run_id"],
        generation_source: row["generation_source"],
        status: row["status"],
        created_at: row["created_at"],
        updated_at: row["updated_at"],
        matched_columns:,
        creator_service: creator_service_for(table, row),
        display_path: display_path_for(table, row)
      }.compact
    end

    def business_id_for(table, row)
      case table
      when "serp_results"
        SerpAnalysis.find_by(id: row["serp_analysis_id"])&.business_id
      when "action_candidate_score_snapshots"
        ActionCandidate.find_by(id: row["action_candidate_id"])&.business_id
      when "action_executions"
        ActionExecution.find_by(id: row["id"])&.business&.id
      end
    end

    def creator_service_for(table, row)
      case table
      when "serp_results"
        "Aicoo::Serp::ScanRunner or SerpAnalysisImportService"
      when "serp_analyses"
        "Aicoo::Serp::ScanRunner or SerpAnalysisImportService"
      when "action_candidates"
        case row["generation_source"]
        when "integrated_decision" then "Aicoo::IntegratedDecisionEngine"
        when "serp" then "SERP candidate generator / legacy SERP ActionCandidate path"
        when "business_analyzer" then "MetricActionCandidateGenerator / BusinessAnalyzer"
        else "ActionCandidate generator source=#{row['generation_source']}"
        end
      when "auto_revision_tasks"
        "AutoRevisionTask.from_action_candidate / AicooAutoRevisionQueueBuilderService"
      when "action_executions"
        "ActionExecution from approved ActionCandidate"
      when "codex_prompt_drafts", "codex_submissions"
        "Aicoo::CodexPromptDraftBuilder / Aicoo::CodexSubmissionBuilder"
      else
        "unknown"
      end
    end

    def display_path_for(table, row)
      case table
      when "action_candidates" then "/action_candidates/#{row['id']}"
      when "auto_revision_tasks" then "/auto_revision_tasks/#{row['id']}"
      when "codex_submissions" then "/admin/codex_submissions/#{row['id']}"
      when "serp_analyses" then "/admin/serp_settings"
      when "serp_results" then "/admin/serp_settings"
      end
    end

    def repair!(matches)
      repairs = []
      action_candidate_ids = matches.filter_map { |match| match[:id] if match[:table] == "action_candidates" }
      action_candidate_ids += matches.filter_map { |match| match[:action_candidate_id] }
      action_candidate_ids.uniq.compact.each do |id|
        candidate = ActionCandidate.find_by(id:)
        next unless candidate

        unless candidate.status.in?(%w[archived rejected done])
          candidate.update!(
            status: "archived",
            metadata: candidate.metadata.to_h.merge(
              "archived_reason" => "unrelated_serp_result_contamination",
              "archived_url" => url,
              "archived_at" => Time.current.iso8601,
              "archived_by" => "Aicoo::UrlContaminationTracer"
            )
          )
          repairs << { table: "action_candidates", id: candidate.id, action: "archived" }
        end

        candidate.auto_revision_tasks.active.find_each do |task|
          task.update!(status: "canceled", metadata: task.metadata.to_h.merge("canceled_reason" => "action_candidate_archived_unrelated_serp_result", "canceled_url" => url))
          repairs << { table: "auto_revision_tasks", id: task.id, action: "canceled" }
        end

        ActionExecution.where(action_candidate: candidate).where.not(status: %w[completed failed cancelled]).find_each do |execution|
          execution.cancel!
          repairs << { table: "action_executions", id: execution.id, action: "cancelled" }
        end
      end
      repairs
    end

    def cause_for(matches)
      return "該当URLは#{Rails.env} DB内に存在しません。" if matches.empty?
      return "Aicoo::IntegratedDecisionEngineがSERP関連度を十分に確認せず、SERP上位URLをActionCandidateの根拠/表示情報へ混入させていました。" if matches.any? { |m| m[:table] == "action_candidates" && m[:generation_source] == "integrated_decision" }
      return "legacy SERP ActionCandidate経路がSERP上位URLをActionCandidateの根拠/表示情報へ混入させていました。" if matches.any? { |m| m[:table] == "action_candidates" && m[:generation_source] == "serp" }
      return "ActionCandidateExecutionBrief/Codex Prompt系の保存済みスナップショットが、過去のSERP上位URLを表示しています。" if matches.any? { |m| m[:table].in?(%w[auto_revision_tasks action_executions codex_prompt_drafts codex_submissions]) }

      "SerpResult/SerpAnalysisには存在しますが、ActionCandidate化された証跡はありません。"
    end

    def display_source_for(matches)
      matches.find { |m| m[:table] == "action_candidates" } ||
        matches.find { |m| m[:table].in?(%w[auto_revision_tasks action_executions codex_prompt_drafts codex_submissions]) } ||
        matches.find { |m| m[:table] == "serp_results" } ||
        matches.first
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
