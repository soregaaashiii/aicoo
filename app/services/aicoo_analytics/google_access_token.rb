module AicooAnalytics
  class GoogleAccessToken
    def initialize(setting)
      @setting = setting
    end

    def call
      oauth_client.access_token
    end

    def credential_source_summary
      [
        "client_id_source=#{credential_source(:client_id)}",
        "client_secret_source=#{credential_source(:client_secret)}",
        "refresh_token_source=#{credential_source(:refresh_token)}",
        "credentials_json_source=#{credentials_json_source}",
        "oauth_connected_at=#{oauth_connected_at_status}"
      ].join(" ")
    end

    private

    attr_reader :setting

    def oauth_client
      GoogleOauthClient.new(
        client_id: credential_value(:client_id),
        client_secret: credential_value(:client_secret),
        refresh_token: credential_value(:refresh_token),
        credential_source_summary:
      )
    end

    def credential_value(key)
      credential_set.fetch(key)
    end

    def credential_source(key)
      credential_set_source
    end

    def credential_set
      @credential_set ||=
        case setting.authentication_mode
        when "individual"
          individual_credential_set
        else
          shared_credential_set
        end
    end

    def credential_set_source
      @credential_set_source ||=
        case setting.authentication_mode
        when "individual"
          individual_credential_source
        else
          shared_credential_source
        end
    end

    def individual_credential_set
      if individual_setting_credentials_present?
        setting_credentials
      elsif env_credentials_present?
        env_credentials
      else
        missing_credentials
      end
    end

    def individual_credential_source
      if individual_setting_credentials_present?
        "setting"
      elsif env_credentials_present?
        "env"
      else
        "missing"
      end
    end

    def shared_credential_set
      if common_google_credential.present?
        google_credential_credentials
      elsif env_credentials_present?
        env_credentials
      else
        missing_credentials
      end
    end

    def shared_credential_source
      if common_google_credential.present?
        "google_credential"
      elsif env_credentials_present?
        "env"
      else
        "missing"
      end
    end

    def individual_setting_credentials_present?
      setting.client_id.present? && setting.client_secret.present? && setting.refresh_token.present?
    end

    def common_google_credential
      @common_google_credential ||= begin
        credential = setting.google_credential
        credential = AicooGoogleCredential.default unless credential&.enabled? && credential.connected?
        credential if credential&.enabled? && credential.connected?
      end
    end

    def env_credentials_present?
      env_keys.values.all? { |key| ENV[key].present? }
    end

    def setting_credentials
      {
        client_id: setting.client_id,
        client_secret: setting.client_secret,
        refresh_token: setting.refresh_token
      }
    end

    def google_credential_credentials
      {
        client_id: common_google_credential.client_id,
        client_secret: common_google_credential.client_secret,
        refresh_token: common_google_credential.refresh_token
      }
    end

    def env_credentials
      {
        client_id: ENV["GOOGLE_CLIENT_ID"],
        client_secret: ENV["GOOGLE_CLIENT_SECRET"],
        refresh_token: ENV["GOOGLE_REFRESH_TOKEN"]
      }
    end

    def missing_credentials
      {
        client_id: nil,
        client_secret: nil,
        refresh_token: nil
      }
    end

    def env_key(key)
      env_keys.fetch(key)
    end

    def env_keys
      {
        client_id: "GOOGLE_CLIENT_ID",
        client_secret: "GOOGLE_CLIENT_SECRET",
        refresh_token: "GOOGLE_REFRESH_TOKEN"
      }
    end

    def credentials_json_source
      setting.credentials_json.present? ? "setting" : "missing"
    end

    def oauth_connected_at_status
      setting.oauth_connected_at.present? ? "present" : "missing"
    end

    def parsed_credentials
      @parsed_credentials ||= JSON.parse(setting.credentials_json.presence || "{}")
    rescue JSON::ParserError
      {}
    end
  end
end
