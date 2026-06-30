module Aicoo
  class ActivityIngestor
    Result = Data.define(:activity_log, :queued, :business, :error_message) do
      def saved?
        activity_log.present?
      end

      def queued?
        queued.present?
      end
    end

    DEFAULT_SOURCE_APP = "aicoo".freeze

    class << self
      def call(...)
        new.call(...)
      end
    end

    def call(record:, action:, business: nil, source_app: nil, metadata: {})
      source_app ||= source_app_for(record, metadata)
      resolved_business = business || business_for(record, source_app:, metadata:)
      attributes = attributes_for(record, action:, source_app:, metadata:)

      if resolved_business
        activity_log = BusinessActivityLog.record!(business: resolved_business, attributes:)
        Result.new(activity_log:, queued: nil, business: resolved_business, error_message: nil)
      else
        queued = queue_unlinked_activity!(attributes, record:, metadata:)
        Result.new(activity_log: nil, queued:, business: nil, error_message: queued.error_message)
      end
    rescue StandardError => e
      Rails.logger.warn("[AICOO ActivityIngestor] failed #{record.class.name}##{record.try(:id)} #{action}: #{e.class}: #{e.message}")
      Result.new(activity_log: nil, queued: nil, business: nil, error_message: "#{e.class}: #{e.message}")
    end

    private

    def attributes_for(record, action:, source_app:, metadata:)
      profile = profile_for(record, action)
      occurred_at = occurred_at_for(record)
      {
        source_app:,
        activity_type: profile.fetch(:activity_type),
        resource_type: record.class.name,
        resource_id: record_id(record),
        title: title_for(record, profile),
        occurred_at:,
        detected_at: Time.current,
        changed_fields: changed_fields_for(record),
        before_snapshot: before_snapshot_for(record),
        after_snapshot: after_snapshot_for(record),
        diff_summary: diff_summary_for(record, profile),
        metadata: metadata_for(record, profile, metadata),
        estimated_work_seconds: profile[:estimated_work_seconds],
        source_method: "logger",
        idempotency_key: idempotency_key_for(record, profile.fetch(:activity_type), occurred_at)
      }
    end

    def profile_for(record, action)
      resource_type = record.class.name
      case resource_type
      when "Shop"
        shop_profile(record, action)
      when "Article"
        article_profile(action)
      when "AicooLabLandingPage"
        landing_page_profile(record, action)
      when "RevenueEvent"
        revenue_event_profile(action)
      when "ActionResult"
        action_result_profile(action)
      else
        generic_profile(resource_type, action)
      end
    end

    def shop_profile(record, action)
      case action.to_sym
      when :create
        { activity_type: "shop_created", title_template: "店舗を追加: %{name}", estimated_work_seconds: 20 }
      when :destroy
        { activity_type: "shop_deleted", title_template: "店舗を削除: %{name}", estimated_work_seconds: 15 }
      else
        activity_type = changed_field_names(record).include?("smoking_status") ? "smoking_status_updated" : "shop_profile_updated"
        { activity_type:, title_template: "店舗を更新: %{name}", estimated_work_seconds: 30 }
      end
    end

    def article_profile(action)
      case action.to_sym
      when :create
        { activity_type: "article_created", title_template: "記事を作成: %{title}", estimated_work_seconds: 180 }
      when :destroy
        { activity_type: "article_deleted", title_template: "記事を削除: %{title}", estimated_work_seconds: 60 }
      else
        { activity_type: "article_updated", title_template: "記事を更新: %{title}", estimated_work_seconds: 180 }
      end
    end

    def landing_page_profile(record, action)
      activity_type = if action.to_sym == :update && status_changed_to_published?(record)
        "landing_page_published"
      else
        "landing_page_#{action}"
      end
      { activity_type:, title_template: "LPを更新: %{headline}", estimated_work_seconds: 120 }
    end

    def revenue_event_profile(action)
      { activity_type: "revenue_event_#{action}", title_template: "収益イベントを記録: %{amount}", estimated_work_seconds: 20 }
    end

    def action_result_profile(action)
      { activity_type: "action_result_#{action}", title_template: "改善結果を記録: %{id}", estimated_work_seconds: 60 }
    end

    def generic_profile(resource_type, action)
      { activity_type: "#{resource_type.underscore}_#{action}", title_template: "#{resource_type}を更新: %{id}", estimated_work_seconds: nil }
    end

    def title_for(record, profile)
      template = profile.fetch(:title_template)
      template % template_values(record)
    rescue KeyError
      "#{record.class.name}を更新: #{record_id(record)}"
    end

    def template_values(record)
      record_attributes(record).symbolize_keys.merge(id: record_id(record))
    end

    def record_attributes(record)
      record.respond_to?(:attributes) ? record.attributes : {}
    end

    def record_id(record)
      record.try(:id).presence || "unknown"
    end

    def changed_fields_for(record)
      changes = previous_changes_for(record)
      return record_attributes(record) if changes.empty?

      changes.transform_values { |values| Array(values).last }
    end

    def before_snapshot_for(record)
      previous_changes_for(record).transform_values { |values| Array(values).first }
    end

    def after_snapshot_for(record)
      changed_fields_for(record)
    end

    def previous_changes_for(record)
      return record.previous_changes.to_h.except("created_at", "updated_at") if record.respond_to?(:previous_changes)

      {}
    end

    def changed_field_names(record)
      previous_changes_for(record).keys
    end

    def diff_summary_for(record, profile)
      "#{record.class.name}##{record_id(record)} #{profile.fetch(:activity_type)}"
    end

    def metadata_for(record, profile, metadata)
      record_metadata = {}
      %w[area smoking_status station source tabelog_url slug target_keyword status public_status].each do |field|
        record_metadata[field] = record.public_send(field) if record.respond_to?(field)
      end
      record_metadata.compact.merge(metadata.to_h).merge("activity_profile" => profile.fetch(:activity_type))
    end

    def occurred_at_for(record)
      record.try(:updated_at) || record.try(:created_at) || Time.current
    end

    def idempotency_key_for(record, activity_type, occurred_at)
      [
        "activity_ingestor",
        source_app_for(record, {}),
        record.class.name,
        activity_type,
        record_id(record),
        (occurred_at.to_f * 1000).to_i
      ].join(":")
    end

    def source_app_for(record, metadata)
      metadata.to_h[:source_app].presence ||
        metadata.to_h["source_app"].presence ||
        record.try(:source_app).presence ||
        record.try(:app_key).presence ||
        source_app_from_diff_rule(record) ||
        DEFAULT_SOURCE_APP
    end

    def source_app_from_diff_rule(record)
      SourceAppConnection.enabled.active
                         .joins(:source_app_diff_rules)
                         .where(source_app_diff_rules: { resource_type: record.class.name, enabled: true })
                         .order(:id)
                         .pick(:source_app)
    end

    def business_for(record, source_app:, metadata:)
      return record.business if record.respond_to?(:business) && record.business
      return Business.find_by(id: record.business_id) if record.respond_to?(:business_id) && record.business_id.present?

      metadata_business(metadata) ||
        business_from_connection(source_app) ||
        business_from_record_keys(record, metadata)
    end

    def metadata_business(metadata)
      attrs = metadata.to_h
      return Business.find_by(id: attrs[:business_id] || attrs["business_id"]) if attrs[:business_id].present? || attrs["business_id"].present?

      slug = attrs[:business_slug].presence || attrs["business_slug"].presence
      return unless slug

      Business.real_businesses.find_by(project_key: slug) if Business.column_names.include?("project_key")
    end

    def business_from_connection(source_app)
      SourceAppConnection.enabled.active.find_by(source_app:)&.business
    end

    def business_from_record_keys(record, metadata)
      app_key = metadata.to_h[:app_key].presence || metadata.to_h["app_key"].presence || record.try(:app_key).presence
      if app_key && Business.column_names.include?("project_key")
        business = Business.real_businesses.find_by(project_key: app_key)
        return business if business
      end

      record.try(:business_slug).presence && Business.real_businesses.find_by(name: record.business_slug)
    end

    def status_changed_to_published?(record)
      changes = previous_changes_for(record)
      Array(changes["public_status"]).last == "published" || Array(changes["status"]).last == "published"
    end

    def queue_unlinked_activity!(attributes, record:, metadata:)
      AicooActivityLogQueue.create!(
        payload: attributes,
        idempotency_key: attributes[:idempotency_key],
        error_message: "Businessに紐付けできないためActivity Log化を保留しました",
        metadata: metadata.to_h.merge(
          "unlinked_activity" => true,
          "resource_type" => record.class.name,
          "resource_id" => record_id(record)
        ),
        next_retry_at: 1.hour.from_now
      )
    end
  end
end
