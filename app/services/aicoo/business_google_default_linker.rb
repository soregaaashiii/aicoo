module Aicoo
  class BusinessGoogleDefaultLinker
    GOOGLE_SOURCE_TYPES = %w[gsc ga4].freeze

    Result = Data.define(:business, :linked_settings, :skipped_sources) do
      def linked_count = linked_settings.size
      def linked? = linked_count.positive?
    end

    def self.call(...)
      new(...).call
    end

    def initialize(business, source_types: GOOGLE_SOURCE_TYPES)
      @business = business
      @source_types = source_types.map(&:to_s) & GOOGLE_SOURCE_TYPES
      @linked_settings = []
      @skipped_sources = {}
    end

    def call
      return result_with_skip("business_not_eligible") unless eligible?

      source_types.each { |source_type| link_source(source_type) }
      result
    end

    private

    attr_reader :business, :source_types, :linked_settings, :skipped_sources

    def eligible?
      business.created_by_aicoo? &&
        !business.system_business? &&
        business.aicoo_internal_codex?
    end

    def link_source(source_type)
      setting = business.business_data_source_settings.find_or_initialize_by(source_key: source_type)
      if business_identifier_present?(setting, source_type)
        skipped_sources[source_type] = "already_business_configured"
        return
      end

      analytics_setting = default_analytics_setting(source_type)
      unless analytics_setting
        skipped_sources[source_type] = "global_setting_missing"
        return
      end

      identifier = identifier_for(analytics_setting, source_type)
      if identifier.blank?
        skipped_sources[source_type] = "global_identifier_missing"
        return
      end

      credential = analytics_setting.google_credential || AicooGoogleCredential.default
      connection_status = google_credential_available?(credential) ? "linked" : "needs_attention"
      setting.assign_attributes(
        enabled: true,
        connection_status:,
        property_identifier: identifier,
        credential_reference: credential&.name || "AICOO全体Google認証",
        metadata: setting.metadata.to_h.merge(
          "connection_fields" => setting.connection_field_values.merge(identifier_key(source_type) => identifier),
          "source_binding" => setting.metadata.to_h.fetch("source_binding", {}).merge(
            "use_global" => "1",
            "inherited_from" => "analytics_source_setting"
          ),
          "google_credential_id" => credential&.id,
          "inherited_analytics_source_setting_id" => analytics_setting.id,
          "auto_linked_by" => self.class.name,
          "auto_linked_at" => Time.current.iso8601
        ).compact
      )
      setting.save!
      linked_settings << setting
    end

    def result_with_skip(reason)
      source_types.each { |source_type| skipped_sources[source_type] = reason }
      result
    end

    def result
      Result.new(business:, linked_settings:, skipped_sources:)
    end

    def business_identifier_present?(setting, source_type)
      return false unless setting.persisted? && setting.enabled?

      setting.connection_field_value(identifier_key(source_type)).present? ||
        setting.property_identifier.present?
    end

    def default_analytics_setting(source_type)
      AnalyticsSourceSetting
        .includes(:google_credential, :aicoo_analytics_site)
        .where(source_type:, enabled: true)
        .order(Arel.sql("CASE WHEN aicoo_analytics_site_id IS NULL THEN 0 ELSE 1 END"), created_at: :desc)
        .find { |setting| identifier_for(setting, source_type).present? }
    end

    def identifier_for(setting, source_type)
      source_type == "gsc" ? setting.site_url.presence : setting.property_id.presence
    end

    def identifier_key(source_type)
      source_type == "gsc" ? "site_url" : "property_id"
    end

    def google_credential_available?(credential)
      credential&.connected? && !credential.token_expired? && !credential.reauthentication_required?
    end
  end
end
