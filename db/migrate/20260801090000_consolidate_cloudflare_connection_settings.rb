class ConsolidateCloudflareConnectionSettings < ActiveRecord::Migration[8.0]
  class MigrationProfile < ActiveRecord::Base
    self.table_name = "data_source_cost_profiles"
  end

  class MigrationBusinessSetting < ActiveRecord::Base
    self.table_name = "business_data_source_settings"
  end

  SECRET_KEYS = %w[api_token access_token refresh_token token_expires_at oauth_scope].freeze

  def up
    profile = MigrationProfile.find_or_initialize_by(source_key: "cloudflare_pages")
    profile.assign_attributes(
      name: "Cloudflare Pages",
      execution_mode: "auto",
      enabled: true
    )

    profile_metadata = profile.metadata.to_h
    credentials = profile_metadata.fetch("credentials", {}).to_h
    cloudflare = profile_metadata.fetch("cloudflare", {}).to_h
    cloudflare["default_project_name"] ||= credentials.delete("project_name").presence || "aicoo-lp"

    MigrationBusinessSetting.where(source_key: "cloudflare_pages").find_each do |setting|
      metadata = setting.metadata.to_h
      legacy_credentials = metadata.fetch("credentials", {}).to_h
      connection_fields = metadata.fetch("connection_fields", {}).to_h

      credentials["account_id"] ||= legacy_credentials["account_id"].presence || metadata["account_id"].presence
      SECRET_KEYS.each do |key|
        credentials[key] ||= legacy_credentials[key].presence || metadata[key].presence
      end

      project_name = setting.property_identifier.presence ||
        metadata["project_name"].presence ||
        connection_fields["project_name"].presence ||
        legacy_credentials["project_name"].presence
      production_url = setting.endpoint_url.presence ||
        metadata["production_url"].presence ||
        connection_fields["production_url"].presence

      sanitized_metadata = metadata.except("account_id", *SECRET_KEYS)
      sanitized_metadata["credentials"] = legacy_credentials.except("account_id", "project_name", *SECRET_KEYS)
      sanitized_metadata.delete("credentials") if sanitized_metadata["credentials"].empty?
      sanitized_metadata["connection_fields"] = connection_fields.except("account_id", "project_name", *SECRET_KEYS)
      sanitized_metadata.delete("connection_fields") if sanitized_metadata["connection_fields"].empty?
      sanitized_metadata["source_binding"] = sanitized_metadata.fetch("source_binding", {}).merge("use_global" => "1")
      sanitized_metadata["project_name"] = project_name if project_name
      sanitized_metadata["production_url"] = production_url if production_url

      setting.update_columns(
        property_identifier: project_name,
        endpoint_url: production_url,
        credential_reference: "AICOO全体Cloudflare認証",
        metadata: sanitized_metadata,
        updated_at: Time.current
      )
    end

    cloudflare["authentication_mode"] ||= credentials["access_token"].present? ? "oauth" : "api_token"
    cloudflare["status"] ||= credentials["account_id"].present? && (credentials["access_token"].present? || credentials["api_token"].present?) ? "connected" : "disconnected"
    profile.metadata = profile_metadata.merge(
      "credentials" => credentials.compact,
      "cloudflare" => cloudflare
    )
    profile.save!
  end

  def down
    # Authentication remains valid in the global record; business selections are not destructive.
  end
end
