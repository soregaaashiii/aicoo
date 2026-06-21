#!/usr/bin/env ruby

require "json"
require "net/http"
require "securerandom"
require "uri"

CLIENT_ID = ENV["GOOGLE_CLIENT_ID"]
CLIENT_SECRET = ENV["GOOGLE_CLIENT_SECRET"]
SCOPE = "https://www.googleapis.com/auth/webmasters.readonly"
REDIRECT_URI = ENV.fetch("GOOGLE_REDIRECT_URI", "http://127.0.0.1:3000/oauth2callback")
AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")

def abort_with(message)
  warn message
  exit 1
end

abort_with "GOOGLE_CLIENT_ID is not set." if CLIENT_ID.to_s.empty?
abort_with "GOOGLE_CLIENT_SECRET is not set." if CLIENT_SECRET.to_s.empty?

state = SecureRandom.hex(16)
auth_uri = URI(AUTH_ENDPOINT)
auth_uri.query = URI.encode_www_form(
  client_id: CLIENT_ID,
  redirect_uri: REDIRECT_URI,
  response_type: "code",
  scope: SCOPE,
  access_type: "offline",
  prompt: "consent",
  state:
)

puts
puts "Redirect URI used by this script:"
puts REDIRECT_URI
puts
puts "Register this exact value in Google Cloud Console:"
puts "APIs & Services > Credentials > OAuth 2.0 Client ID > Authorized redirect URIs"
puts REDIRECT_URI
puts
puts "Open this URL in your browser and approve Search Console readonly access:"
puts
puts auth_uri
puts

if RUBY_PLATFORM.match?(/darwin/)
  system("open", auth_uri.to_s)
end

puts "After approval, Google will redirect to the URL above."
puts "If the browser shows a connection error, copy the full URL from the address bar."
puts
print "Paste the authorization code or full redirected URL here: "
input = STDIN.gets&.strip
code = if input&.start_with?("http")
  URI(input).then { |uri| URI.decode_www_form(uri.query.to_s).to_h["code"] }
else
  input
end
abort_with "Authorization code is blank." if code.to_s.empty?

response = Net::HTTP.post_form(
  TOKEN_ENDPOINT,
  client_id: CLIENT_ID,
  client_secret: CLIENT_SECRET,
  code:,
  grant_type: "authorization_code",
  redirect_uri: REDIRECT_URI
)

unless response.is_a?(Net::HTTPSuccess)
  abort_with "Google token exchange failed: #{response.code} #{response.body}"
end

token = JSON.parse(response.body)

puts
puts "GOOGLE_REFRESH_TOKEN:"
puts token.fetch("refresh_token")
puts
puts "Add it to the same shell where you start Rails:"
puts %(export GOOGLE_REFRESH_TOKEN="#{token.fetch("refresh_token")}")
puts
