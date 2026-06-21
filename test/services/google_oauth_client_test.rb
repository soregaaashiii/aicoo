require "test_helper"

class GoogleOauthClientTest < ActiveSupport::TestCase
  test "refreshes access token with refresh_token grant" do
    captured_form = nil
    response = FakeHttpResponse.new(success: true, code: "200", body: '{"access_token":"new-access-token"}')

    with_post_form_stub(response, captured: ->(form) { captured_form = form }) do
      token = GoogleOauthClient.new(
        client_id: "client-id",
        client_secret: "client-secret",
        refresh_token: "refresh-token"
      ).access_token

      assert_equal "new-access-token", token
    end

    assert_equal "client-id", captured_form[:client_id]
    assert_equal "client-secret", captured_form[:client_secret]
    assert_equal "refresh-token", captured_form[:refresh_token]
    assert_equal "refresh_token", captured_form[:grant_type]
  end

  test "token refresh failure includes credential sources without secret values" do
    response = FakeHttpResponse.new(
      success: false,
      code: "401",
      body: '{"error":"unauthorized_client"}'
    )

    error = assert_raises(GoogleOauthClient::Error) do
      with_post_form_stub(response) do
        GoogleOauthClient.new(
          client_id: "client-id",
          client_secret: "client-secret",
          refresh_token: "refresh-token",
          credential_source_summary: "client_id_source=setting client_secret_source=setting refresh_token_source=setting credentials_json_source=missing"
        ).access_token
      end
    end

    assert_includes error.message, "unauthorized_client"
    assert_includes error.message, "client_id_source=setting"
    assert_includes error.message, "client_secret_source=setting"
    assert_includes error.message, "refresh_token_source=setting"
    refute_includes error.message, "client-secret"
    refute_includes error.message, "refresh-token"
  end

  private

  def with_post_form_stub(response, captured: nil)
    original_post_form = Net::HTTP.method(:post_form)
    Net::HTTP.define_singleton_method(:post_form) do |_uri, form|
      captured&.call(form)
      response
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:post_form) do |*args, **kwargs, &block|
      original_post_form.call(*args, **kwargs, &block)
    end
  end

  class FakeHttpResponse
    attr_reader :code, :body

    def initialize(success:, code:, body:)
      @success = success
      @code = code
      @body = body
    end

    def is_a?(klass)
      klass == Net::HTTPSuccess ? @success : super
    end
  end
end
