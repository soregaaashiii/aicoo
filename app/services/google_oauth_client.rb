require "net/http"
require "json"

class GoogleOauthClient
  TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")

  class Error < StandardError; end
  class MissingCredentialsError < Error; end

  def initialize(
    client_id: ENV["GOOGLE_CLIENT_ID"],
    client_secret: ENV["GOOGLE_CLIENT_SECRET"],
    refresh_token: ENV["GOOGLE_REFRESH_TOKEN"],
    credential_source_summary: nil
  )
    @client_id = client_id
    @client_secret = client_secret
    @refresh_token = refresh_token
    @credential_source_summary = credential_source_summary
  end

  def access_token
    validate_credentials!

    response = Net::HTTP.post_form(
      TOKEN_ENDPOINT,
      client_id: @client_id,
      client_secret: @client_secret,
      refresh_token: @refresh_token,
      grant_type: "refresh_token"
    )

    raise Error, error_message("Google OAuth error: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("access_token")
  rescue JSON::ParserError, KeyError => e
    raise Error, error_message("Google OAuth response could not be parsed: #{e.message}")
  end

  private

  attr_reader :credential_source_summary

  def validate_credentials!
    missing = {
      GOOGLE_CLIENT_ID: @client_id,
      GOOGLE_CLIENT_SECRET: @client_secret,
      GOOGLE_REFRESH_TOKEN: @refresh_token
    }.select { |_key, value| value.blank? }.keys

    return if missing.empty?

    raise MissingCredentialsError, error_message("#{missing.join(', ')} is not set.")
  end

  def error_message(message)
    [ message, credential_source_summary ].compact_blank.join(" ")
  end
end
