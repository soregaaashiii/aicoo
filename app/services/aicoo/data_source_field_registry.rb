module Aicoo
  module DataSourceFieldRegistry
    Field = Data.define(:key, :label, :secret, :placeholder)

    GLOBAL_CREDENTIAL_FIELDS = {
      "gsc" => [
        Field.new(key: "google_client_id", label: "GOOGLE_CLIENT_ID", secret: false, placeholder: "AICOO共通Google認証を使う場合は空でOK"),
        Field.new(key: "google_client_secret", label: "GOOGLE_CLIENT_SECRET", secret: true, placeholder: "AICOO共通Google認証を使う場合は空でOK"),
        Field.new(key: "google_refresh_token", label: "GOOGLE_REFRESH_TOKEN", secret: true, placeholder: "AICOO共通Google認証を使う場合は空でOK")
      ],
      "ga4" => [
        Field.new(key: "google_client_id", label: "GOOGLE_CLIENT_ID", secret: false, placeholder: "AICOO共通Google認証を使う場合は空でOK"),
        Field.new(key: "google_client_secret", label: "GOOGLE_CLIENT_SECRET", secret: true, placeholder: "AICOO共通Google認証を使う場合は空でOK"),
        Field.new(key: "google_refresh_token", label: "GOOGLE_REFRESH_TOKEN", secret: true, placeholder: "AICOO共通Google認証を使う場合は空でOK")
      ],
      "serp" => [
        Field.new(key: "api_key", label: "API Key", secret: true, placeholder: "SERP API key"),
        Field.new(key: "endpoint", label: "Endpoint", secret: false, placeholder: "https://...")
      ],
      "youtube" => [
        Field.new(key: "api_key", label: "API Key", secret: true, placeholder: "YouTube Data API key")
      ],
      "x" => [
        Field.new(key: "bearer_token", label: "Bearer Token", secret: true, placeholder: "X Bearer Token"),
        Field.new(key: "api_key", label: "API Key", secret: true, placeholder: "X API Key")
      ],
      "google_ads" => [
        Field.new(key: "client_id", label: "client_id", secret: false, placeholder: "Google Ads OAuth client_id"),
        Field.new(key: "client_secret", label: "client_secret", secret: true, placeholder: "Google Ads OAuth client_secret"),
        Field.new(key: "refresh_token", label: "refresh_token", secret: true, placeholder: "Google Ads refresh_token"),
        Field.new(key: "developer_token", label: "developer_token", secret: true, placeholder: "Google Ads developer_token")
      ],
      "meta_ads" => [
        Field.new(key: "app_id", label: "app_id", secret: false, placeholder: "Meta app_id"),
        Field.new(key: "app_secret", label: "app_secret", secret: true, placeholder: "Meta app_secret"),
        Field.new(key: "access_token", label: "access_token", secret: true, placeholder: "Meta access_token")
      ],
      "clarity" => [
        Field.new(key: "api_token", label: "API token", secret: true, placeholder: "Clarity API token")
      ],
      "openai" => [
        Field.new(key: "api_key", label: "API Key", secret: true, placeholder: "OpenAI API key")
      ]
    }.freeze

    BUSINESS_CONNECTION_FIELDS = {
      "gsc" => [
        Field.new(key: "site_url", label: "GSC site_url", secret: false, placeholder: "sc-domain:suelog.jp")
      ],
      "ga4" => [
        Field.new(key: "property_id", label: "GA4 property_id", secret: false, placeholder: "properties/536889590")
      ],
      "serp" => [
        Field.new(key: "keyword", label: "keyword", secret: false, placeholder: "梅田 喫煙所"),
        Field.new(key: "location", label: "location", secret: false, placeholder: "Japan / Osaka"),
        Field.new(key: "device", label: "device", secret: false, placeholder: "desktop / mobile")
      ],
      "youtube" => [
        Field.new(key: "channel_id", label: "channel_id", secret: false, placeholder: "UC..."),
        Field.new(key: "keyword", label: "keyword", secret: false, placeholder: "シーシャ 大阪")
      ],
      "x" => [
        Field.new(key: "search_query", label: "検索query", secret: false, placeholder: "梅田 喫煙所 OR 喫煙カフェ")
      ],
      "google_ads" => [
        Field.new(key: "customer_id", label: "customer_id", secret: false, placeholder: "123-456-7890")
      ],
      "meta_ads" => [
        Field.new(key: "ad_account_id", label: "ad_account_id", secret: false, placeholder: "act_...")
      ],
      "clarity" => [
        Field.new(key: "project_id", label: "project_id", secret: false, placeholder: "Clarity project_id")
      ]
    }.freeze

    module_function

    def global_credential_fields(source_key)
      GLOBAL_CREDENTIAL_FIELDS.fetch(source_key.to_s, [])
    end

    def business_connection_fields(source_key)
      BUSINESS_CONNECTION_FIELDS.fetch(source_key.to_s, [])
    end
  end
end
