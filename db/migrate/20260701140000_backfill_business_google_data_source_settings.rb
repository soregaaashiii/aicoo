class BackfillBusinessGoogleDataSourceSettings < ActiveRecord::Migration[8.1]
  class MigrationBusiness < ActiveRecord::Base
    self.table_name = "businesses"
  end

  class MigrationBusinessDataSourceSetting < ActiveRecord::Base
    self.table_name = "business_data_source_settings"
  end

  class MigrationAnalyticsSourceSetting < ActiveRecord::Base
    self.table_name = "analytics_source_settings"
  end

  def up
    now = Time.current
    analytics_settings = MigrationAnalyticsSourceSetting.where(enabled: true).to_a

    MigrationBusiness.find_each do |business|
      backfill_source!(
        business:,
        source_key: "ga4",
        identifier_key: "property_id",
        identifier: analytics_identifier_for(analytics_settings, business, "ga4"),
        analytics_setting: named_setting_for(analytics_settings, business, "ga4"),
        now:
      )
      backfill_source!(
        business:,
        source_key: "gsc",
        identifier_key: "site_url",
        identifier: analytics_identifier_for(analytics_settings, business, "gsc") || business.gsc_site_url,
        analytics_setting: named_setting_for(analytics_settings, business, "gsc"),
        now:
      )
    end
  end

  def down
    # Data backfill only. Keep Business Google settings intact on rollback.
  end

  private

  def backfill_source!(business:, source_key:, identifier_key:, identifier:, analytics_setting:, now:)
    return if identifier.blank?

    setting = MigrationBusinessDataSourceSetting.find_or_initialize_by(
      business_id: business.id,
      source_key:
    )
    metadata = setting.metadata.to_h
    connection_fields = metadata.fetch("connection_fields", {})
    return if setting.property_identifier.present? || connection_fields[identifier_key].present?

    credential_id = analytics_setting&.google_credential_id
    metadata["connection_fields"] = connection_fields.merge(identifier_key => identifier)
    metadata["source_binding"] = metadata.fetch("source_binding", {}).merge("use_global" => "0")
    metadata["google_credential_id"] = credential_id if credential_id.present?

    setting.enabled = true if setting.enabled.nil?
    setting.connection_status = credential_id.present? ? "linked" : "needs_attention"
    setting.property_identifier = identifier
    setting.credential_reference = "Google Credential ##{credential_id}" if credential_id.present?
    setting.metadata = metadata
    setting.created_at ||= now
    setting.updated_at = now
    setting.save!
  end

  def analytics_identifier_for(settings, business, source_key)
    setting = named_setting_for(settings, business, source_key)
    source_key == "ga4" ? setting&.property_id : setting&.site_url
  end

  def named_setting_for(settings, business, source_key)
    settings.find do |setting|
      setting.source_type == source_key &&
        setting.name.to_s.match?(/\A#{Regexp.escape(business.name)}\b/i)
    end
  end
end
