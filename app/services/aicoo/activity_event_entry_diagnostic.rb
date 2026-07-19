module Aicoo
  class ActivityEventEntryDiagnostic
    Event = Data.define(:event_type, :model_name, :resource_type, :source_event, :activity_types, :changed_fields)
    Row = Data.define(
      :event_type,
      :model,
      :record_saved,
      :callback_called,
      :activity_log_record_called,
      :business_activity_log_created,
      :activity_api_sent,
      :skip_reason,
      :exception
    )
    Summary = Data.define(
      :shop_create_count,
      :shop_update_count,
      :article_create_count,
      :article_update_count,
      :record_call_count,
      :business_activity_log_count,
      :activity_api_count,
      :db_diff_count,
      :source_database_configured,
      :source_database_available,
      :activity_api_token_configured,
      :diff_connection_enabled,
      :reason_counts
    )
    Result = Data.define(:rows, :summary)

    EVENTS = [
      Event.new(event_type: "shop_created", model_name: "Suelog::Shop", resource_type: "Shop", source_event: :create, activity_types: %w[shop_created], changed_fields: []),
      Event.new(event_type: "shop_updated", model_name: "Suelog::Shop", resource_type: "Shop", source_event: :update, activity_types: %w[shop_profile_updated smoking_status_updated smoking_verified], changed_fields: []),
      Event.new(event_type: "article_created", model_name: "Suelog::Article", resource_type: "Article", source_event: :create, activity_types: %w[article_created], changed_fields: []),
      Event.new(event_type: "article_updated", model_name: "Suelog::Article", resource_type: "Article", source_event: :update, activity_types: %w[article_updated article_seo_updated article_published], changed_fields: []),
      Event.new(event_type: "seo_improvement", model_name: "Suelog::Article", resource_type: "Article", source_event: :update, activity_types: %w[article_seo_updated], changed_fields: %w[seo_title meta_description slug]),
      Event.new(event_type: "internal_link_addition", model_name: "Suelog::Article", resource_type: "Article", source_event: :update, activity_types: %w[article_updated], changed_fields: %w[body content html markdown]),
      Event.new(event_type: "title_change", model_name: "Suelog::Article", resource_type: "Article", source_event: :update, activity_types: %w[article_updated article_seo_updated], changed_fields: %w[title seo_title]),
      Event.new(event_type: "landing_page_improvement", model_name: "AicooLabLandingPage", resource_type: "AicooLabLandingPage", source_event: :update, activity_types: %w[landing_page_update landing_page_published], changed_fields: [])
    ].freeze

    def initialize(business_id: nil)
      @business_id = business_id.presence
    end

    def call
      business = target_business
      source = source_counts
      logs = business ? business.business_activity_logs : BusinessActivityLog.none
      rows = EVENTS.map { |event| row_for(event, source:, logs:, business:) }

      Result.new(rows:, summary: summary_for(rows, source:, logs:, business:))
    end

    private

    attr_reader :business_id

    def target_business
      return Business.real_businesses.find_by(id: business_id) if business_id

      Business.real_businesses.find_by(project_key: "suelog") ||
        SourceAppConnection.enabled.active.find_by(source_app: "suelog")&.business ||
        Business.real_businesses.find_by(name: "吸えログ")
    end

    def source_counts
      return unavailable_source_counts("suelog_database_url_missing") unless SuelogRecord.configured?

      SuelogRecord.ensure_connection!
      {
        available: true,
        exception: nil,
        shop_create: ::Suelog::Shop.count,
        shop_update: updated_record_count(::Suelog::Shop),
        article_create: ::Suelog::Article.count,
        article_update: updated_record_count(::Suelog::Article)
      }
    rescue StandardError => e
      unavailable_source_counts("#{e.class}: #{e.message}")
    end

    def unavailable_source_counts(error)
      {
        available: false,
        exception: error,
        shop_create: 0,
        shop_update: 0,
        article_create: 0,
        article_update: 0
      }
    end

    def updated_record_count(model)
      return 0 unless model.column_names.include?("created_at") && model.column_names.include?("updated_at")

      model.where("updated_at > created_at").count
    end

    def row_for(event, source:, logs:, business:)
      event_logs = event_logs_for(event, logs)
      source_count = source_count_for(event, source, business:)
      local_callback = local_callback_installed?(event.model_name)
      api_sent = event_logs.any?(&:source_method_logger?)
      activity_created = event_logs.any?

      Row.new(
        event_type: event.event_type,
        model: event.model_name,
        record_saved: source_count.positive?,
        callback_called: api_sent || local_callback,
        activity_log_record_called: record_call_observed?(event_logs),
        business_activity_log_created: activity_created,
        activity_api_sent: api_sent,
        skip_reason: skip_reason_for(event:, source:, source_count:, activity_created:),
        exception: external_event?(event) ? source[:exception] : nil
      )
    end

    def event_logs_for(event, logs)
      records = logs.where(resource_type: event.resource_type, activity_type: event.activity_types).to_a
      return records if event.changed_fields.empty?

      records.select do |activity_log|
        fields = activity_log.metadata.to_h["changed_fields"]
        fields = fields.keys if fields.is_a?(Hash)
        fields = activity_log.changed_fields.to_h.keys if fields.blank?
        (Array(fields).map(&:to_s) & event.changed_fields).any?
      end
    end

    def source_count_for(event, source, business:)
      return business&.aicoo_lab_landing_pages&.count.to_i if event.model_name == "AicooLabLandingPage"

      source.fetch(:"#{event.resource_type.downcase}_#{event.source_event}", 0)
    rescue StandardError
      0
    end

    def local_callback_installed?(model_name)
      klass = model_name.safe_constantize
      klass.present? && klass.included_modules.include?(AicooActivityTrackable) && klass <= ApplicationRecord
    end

    def record_call_observed?(event_logs)
      event_logs.any? do |activity_log|
        activity_log.metadata.to_h.dig("business_activity_log_creation", "persistence_method") == "BusinessActivityLog.record!"
      end
    end

    def skip_reason_for(event:, source:, source_count:, activity_created:)
      return nil if activity_created
      return "source_database_unavailable" if external_event?(event) && !source[:available]
      return "source_record_not_found" unless source_count.positive?

      "activity_api_not_received_and_diff_not_ingested"
    end

    def summary_for(rows, source:, logs:, business:)
      connection = business&.source_app_connections&.find_by(source_app: "suelog")
      log_records = logs.to_a
      Summary.new(
        shop_create_count: source[:shop_create],
        shop_update_count: source[:shop_update],
        article_create_count: source[:article_create],
        article_update_count: source[:article_update],
        record_call_count: log_records.count { |log| record_call_observed?([ log ]) },
        business_activity_log_count: log_records.size,
        activity_api_count: log_records.count(&:source_method_logger?),
        db_diff_count: log_records.count(&:source_method_db_diff?),
        source_database_configured: SuelogRecord.configured?,
        source_database_available: source[:available],
        activity_api_token_configured: activity_api_token_configured?,
        diff_connection_enabled: connection&.enabled? && connection&.status == "active",
        reason_counts: rows.filter_map(&:skip_reason).tally
      )
    end

    def external_event?(event)
      event.model_name.start_with?("Suelog::")
    end

    def activity_api_token_configured?
      ENV["AICOO_ACTIVITY_API_TOKEN"].present? ||
        ENV["AICOO_ACTIVITY_API_KEY"].present? ||
        ENV["AICOO_API_KEY"].present?
    end
  end
end
