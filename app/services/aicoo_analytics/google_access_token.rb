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
        "credentials_json_source=#{credentials_json_source}"
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
      setting_value(key) || env_value(key) || json_value(key)
    end

    def credential_source(key)
      return "setting" if setting_value(key).present?
      return "env" if env_value(key).present?
      return "credentials_json" if json_value(key).present?

      "missing"
    end

    def setting_value(key)
      setting.public_send(key).presence
    end

    def env_value(key)
      ENV[env_key(key)].presence
    end

    def json_value(key)
      parsed_credentials[key.to_s].presence
    end

    def env_key(key)
      {
        client_id: "GOOGLE_CLIENT_ID",
        client_secret: "GOOGLE_CLIENT_SECRET",
        refresh_token: "GOOGLE_REFRESH_TOKEN"
      }.fetch(key)
    end

    def credentials_json_source
      setting.credentials_json.present? ? "setting" : "missing"
    end

    def parsed_credentials
      @parsed_credentials ||= JSON.parse(setting.credentials_json.presence || "{}")
    rescue JSON::ParserError
      {}
    end
  end
end
