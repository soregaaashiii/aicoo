module Aicoo
  class SourceAppDiffDetector
    Result = Struct.new(:created_count, :skipped_count, :error_count, keyword_init: true)

    def call
      result = Result.new(created_count: 0, skipped_count: 0, error_count: 0)
      SourceAppConnection.enabled.active.includes(:business, :source_app_diff_rules).find_each do |connection|
        scan_connection(connection, result)
      end
      result
    end

    private

    def scan_connection(connection, result)
      unless connection.connection_type == "same_database"
        result.skipped_count += 1
        return
      end

      connection.source_app_diff_rules.enabled.each do |rule|
        result.created_count += scan_rule(connection, rule)
      rescue StandardError => e
        result.error_count += 1
        connection.update!(status: "error", last_error: "#{e.class}: #{e.message}")
        Rails.logger.warn("Source app diff rule failed id=#{rule.id}: #{e.class}: #{e.message}")
      end
      connection.update!(status: "active", last_checked_at: Time.current, last_success_at: Time.current, last_error: nil) if result.error_count.zero?
    end

    def scan_rule(connection, rule)
      return 0 unless table_exists?(rule.watched_table)

      rows = changed_rows(rule)
      created_count = 0
      rows.each do |row|
        activity = build_activity(connection, rule, row)
        created_count += 1 if BusinessActivityLog.record!(business: connection.business, attributes: activity).previously_new_record?
      end
      update_cursor!(rule, rows)
      created_count
    end

    def changed_rows(rule)
      cursor = rule.cursor
      quoted_table = ActiveRecord::Base.connection.quote_table_name(rule.watched_table)
      conditions = []
      binds = []
      if cursor.last_checked_at
        conditions << "updated_at > ?"
        binds << cursor.last_checked_at
      end
      if cursor.last_seen_id
        conditions << "id > ?"
        binds << cursor.last_seen_id
      end

      where_sql = conditions.any? ? "WHERE #{conditions.join(' OR ')}" : ""
      sql = ActiveRecord::Base.sanitize_sql([ "SELECT * FROM #{quoted_table} #{where_sql} ORDER BY updated_at ASC, id ASC LIMIT 200", *binds ])
      ActiveRecord::Base.connection.exec_query(sql).to_a
    end

    def build_activity(connection, rule, row)
      fields = Array(rule.watched_fields).select { |field| row.key?(field) }
      metadata_fields = Array(rule.metadata_fields).select { |field| row.key?(field) }
      occurred_at = row["updated_at"] || row["created_at"] || Time.current
      resource_id = row["id"].to_s
      {
        source_app: connection.source_app,
        activity_type: activity_type_for(rule, row),
        resource_type: rule.resource_type,
        resource_id:,
        title: title_for(rule, row),
        occurred_at:,
        detected_at: Time.current,
        changed_fields: fields.index_with { |field| row[field] },
        before_snapshot: {},
        after_snapshot: fields.index_with { |field| row[field] },
        diff_summary: "#{rule.resource_type}##{resource_id} changed fields: #{fields.join(', ')}",
        metadata: metadata_fields.index_with { |field| row[field] }.merge(rule: rule.name),
        estimated_work_seconds: rule.estimated_work_seconds,
        source_method: "db_diff",
        idempotency_key: idempotency_key(connection, rule, row, occurred_at)
      }
    end

    def activity_type_for(rule, row)
      created_at = row["created_at"]
      updated_at = row["updated_at"]
      return rule.activity_type unless created_at && updated_at

      created_at.to_i == updated_at.to_i ? rule.activity_type.sub(/_updated\z/, "_created") : rule.activity_type
    end

    def title_for(rule, row)
      return rule.name if rule.title_template.blank?

      rule.title_template % row.symbolize_keys
    rescue KeyError
      rule.name
    end

    def idempotency_key(connection, rule, row, occurred_at)
      [
        connection.source_app,
        rule.watched_table,
        rule.activity_type,
        row["id"],
        occurred_at.to_i
      ].join(":")
    end

    def update_cursor!(rule, rows)
      return if rows.empty?

      rule.cursor.update!(
        last_checked_at: rows.filter_map { |row| row["updated_at"] }.max || Time.current,
        last_seen_id: rows.filter_map { |row| row["id"] }.max
      )
    end

    def table_exists?(table_name)
      ActiveRecord::Base.connection.data_source_exists?(table_name)
    end
  end
end
