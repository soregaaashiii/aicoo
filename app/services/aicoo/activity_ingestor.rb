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

      def install_model_callbacks!(*model_names)
        model_names.flatten.each do |model_name|
          klass = model_name.to_s.safe_constantize
          unless klass
            Rails.logger.info("[ActivityIngestor] callback install skipped model=#{model_name} reason=constant_not_found")
            next
          end

          if klass.included_modules.include?(AicooActivityTrackable)
            Rails.logger.info("[ActivityIngestor] callback already installed model=#{klass.name}")
            next
          end

          klass.include(AicooActivityTrackable)
          Rails.logger.info("[ActivityIngestor] callback installed model=#{klass.name}")
        end
      end

      def ingest_payload(...)
        new.ingest_payload(...)
      end
    end

    def ingest_payload(business:, payload:)
      attributes = external_attributes_for(payload)
      Rails.logger.info(
        "[ActivityIngestor] API payload start business=#{business.name} " \
        "activity_type=#{attributes[:activity_type]} resource=#{attributes[:resource_type]}##{attributes[:resource_id]}"
      )
      activity_log = BusinessActivityLog.record!(business:, attributes: attributes.merge(source_method: "logger"))
      Rails.logger.info(
        "[ActivityIngestor] API Activity created id=#{activity_log.id} business=#{business.name} " \
        "activity_type=#{activity_log.activity_type} resource=#{activity_log.resource_type}##{activity_log.resource_id}"
      )
      Result.new(activity_log:, queued: nil, business:, error_message: nil)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "[ActivityIngestor] API validation failed business=#{business.try(:name)} " \
        "errors=#{e.record.errors.full_messages.to_sentence} payload=#{safe_log_payload(payload)}"
      )
      Result.new(activity_log: nil, queued: nil, business:, error_message: e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      Rails.logger.warn(
        "[ActivityIngestor] API failed business=#{business.try(:name)} #{e.class}: #{e.message} " \
        "payload=#{safe_log_payload(payload)}"
      )
      Result.new(activity_log: nil, queued: nil, business:, error_message: "#{e.class}: #{e.message}")
    end

    def call(record:, action:, business: nil, source_app: nil, metadata: {})
      log_start(record:, action:)
      source_app ||= source_app_for(record, metadata)
      resolved_business = business || business_for(record, source_app:, metadata:)
      attributes = attributes_for(record, action:, source_app:, metadata:)
      log_business_resolution(record:, business: resolved_business, source_app:)

      if resolved_business
        activity_log = BusinessActivityLog.record!(business: resolved_business, attributes:)
        Rails.logger.info(
          "[ActivityIngestor] Activity created id=#{activity_log.id} " \
          "record=#{record.class.name}##{record_id(record)} business=#{resolved_business.name} " \
          "activity_type=#{activity_log.activity_type} source_method=#{activity_log.source_method}"
        )
        Result.new(activity_log:, queued: nil, business: resolved_business, error_message: nil)
      else
        queued = queue_unlinked_activity!(attributes, record:, metadata:)
        Rails.logger.warn(
          "[ActivityIngestor] Business not found record=#{record.class.name}##{record_id(record)} " \
          "source_app=#{source_app} queued_id=#{queued.id}"
        )
        Result.new(activity_log: nil, queued:, business: nil, error_message: queued.error_message)
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "[ActivityIngestor] validation failed record=#{record.class.name}##{record.try(:id)} " \
        "action=#{action} errors=#{e.record.errors.full_messages.to_sentence}"
      )
      Result.new(activity_log: nil, queued: nil, business: nil, error_message: e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      Rails.logger.warn(
        "[ActivityIngestor] failed record=#{record.class.name}##{record.try(:id)} " \
        "action=#{action}: #{e.class}: #{e.message}"
      )
      Result.new(activity_log: nil, queued: nil, business: nil, error_message: "#{e.class}: #{e.message}")
    end

    private

    def external_attributes_for(payload)
      attrs = hash_for(payload).symbolize_keys
      source_type = attrs[:source_type].presence || attrs[:resource_type].presence || "activity"
      source_id = attrs[:source_id].presence || attrs[:resource_id].presence || "unknown"
      raw_activity_type = attrs[:activity_type].presence || "#{source_type.to_s.underscore}_updated"
      occurred_at = attrs[:occurred_at].presence || Time.current
      metadata = normalized_external_metadata(attrs)
      metadata = metadata.merge("business_key" => attrs[:business_key]) if attrs[:business_key].present?
      activity_type = normalized_external_activity_type(
        attrs.merge(
          source_type:,
          resource_type: attrs[:resource_type].presence || source_type.to_s.camelize,
          activity_type: raw_activity_type,
          metadata:
        )
      )
      metadata = metadata.merge("normalized_activity_type" => activity_type, "raw_activity_type" => raw_activity_type)

      {
        source_app: attrs[:source_app].presence || attrs[:business_key].presence || DEFAULT_SOURCE_APP,
        activity_type:,
        resource_type: attrs[:resource_type].presence || source_type.to_s.camelize,
        resource_id: source_id.to_s,
        title: attrs[:title].presence || activity_type.to_s.humanize,
        occurred_at:,
        detected_at: attrs[:detected_at].presence || Time.current,
        changed_fields: hash_for(attrs[:changed_fields]),
        before_snapshot: hash_for(attrs[:before_snapshot]),
        after_snapshot: hash_for(attrs[:after_snapshot]),
        diff_summary: attrs[:diff_summary].presence || attrs[:summary],
        metadata:,
        estimated_work_seconds: attrs[:estimated_work_seconds],
        idempotency_key: attrs[:idempotency_key]
      }
    end

    def normalized_external_activity_type(attrs)
      return attrs[:activity_type] unless suelog_payload?(attrs)

      resource_type = attrs[:resource_type].to_s
      activity_type = attrs[:activity_type].to_s
      metadata = attrs[:metadata].to_h

      case resource_type
      when "Shop"
        case activity_type
        when "data_added"
          "shop_created"
        when "data_updated"
          if smoking_verification_payload?(attrs)
            "smoking_verified"
          elsif smoking_status_payload?(attrs)
            "smoking_status_updated"
          else
            "shop_profile_updated"
          end
        else
          activity_type
        end
      when "Article"
        { "data_added" => "article_created", "data_updated" => "article_updated" }.fetch(activity_type, activity_type)
      else
        metadata["resource_type"].to_s == "shop" && activity_type == "data_added" ? "shop_created" : activity_type
      end
    end

    def normalized_external_metadata(attrs)
      metadata = hash_for(attrs[:metadata]).deep_stringify_keys
      before_snapshot = hash_for(attrs[:before_snapshot]).deep_stringify_keys
      after_snapshot = hash_for(attrs[:after_snapshot]).deep_stringify_keys
      resource_id = attrs[:resource_id].presence || attrs[:source_id]

      %w[
        area
        station
        smoking_status
        smoking_area
        smoking_type
        last_confirmed_on
        confirmed_at
        phone
        address
        opening_hours
        regular_holiday
        tabelog_url
      ].each do |key|
        metadata[key] = after_snapshot[key] if metadata[key].blank? && after_snapshot[key].present?
      end

      metadata["shop_id"] ||= resource_id.to_s if suelog_shop_payload?(attrs)
      metadata["verified"] = true if suelog_payload?(attrs) && smoking_verification_payload?(attrs.merge(metadata:, before_snapshot:, after_snapshot:))
      metadata["smoking_verified"] = true if metadata["verified"] == true
      metadata["changed_fields"] ||= normalized_changed_fields(attrs)
      metadata
    end

    def suelog_payload?(attrs)
      source_app = attrs[:source_app].presence || attrs[:business_key]
      source_app.to_s.in?(%w[suelog sue-log 吸えログ])
    end

    def suelog_shop_payload?(attrs)
      suelog_payload?(attrs) &&
        (attrs[:resource_type].to_s == "Shop" || attrs[:source_type].to_s == "shop")
    end

    def smoking_verification_payload?(attrs)
      metadata = attrs[:metadata].to_h
      fields = normalized_changed_fields(attrs)
      return true if truthy?(metadata["verified"]) || truthy?(metadata[:verified]) || truthy?(metadata["smoking_verified"])
      return true if metadata["last_confirmed_on"].present? || metadata[:last_confirmed_on].present?

      (fields & %w[smoking_area smoking_type last_confirmed_on smoking_unverified]).any? ||
        metadata.key?("smoking_area") ||
        metadata.key?("smoking_type")
    end

    def smoking_status_payload?(attrs)
      metadata = attrs[:metadata].to_h
      fields = normalized_changed_fields(attrs)
      fields.include?("smoking_status") ||
        metadata.key?("smoking_status") ||
        metadata.key?(:smoking_status)
    end

    def normalized_changed_fields(attrs)
      raw = attrs[:changed_fields]
      case raw
      when ActionController::Parameters
        raw.to_unsafe_h.keys
      when Hash
        raw.keys
      when Array
        raw
      else
        []
      end.map(&:to_s)
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def hash_for(value)
      case value
      when ActionController::Parameters
        value.to_unsafe_h
      when Hash
        value
      else
        {}
      end
    end

    def safe_log_payload(payload)
      hash_for(payload).except(:before_snapshot, :after_snapshot, :metadata).inspect
    end

    def log_start(record:, action:)
      Rails.logger.info("[ActivityIngestor] start record=#{record.class.name}##{record_id(record)} action=#{action}")
    end

    def log_business_resolution(record:, business:, source_app:)
      if business
        Rails.logger.info(
          "[ActivityIngestor] Business=#{business.name} record=#{record.class.name}##{record_id(record)} source_app=#{source_app}"
        )
      else
        Rails.logger.warn("[ActivityIngestor] Business not found record=#{record.class.name}##{record_id(record)} source_app=#{source_app}")
      end
    end

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
