require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "ga4 tag is enabled only in production with measurement id" do
    with_env("GA4_MEASUREMENT_ID", "G-E5KCHJTFVP") do
      with_rails_env("production") do
        assert render_ga4_tag?
        assert_equal "G-E5KCHJTFVP", ga4_measurement_id
      end
    end
  end

  test "ga4 tag is disabled outside production even when measurement id exists" do
    with_env("GA4_MEASUREMENT_ID", "G-E5KCHJTFVP") do
      with_rails_env("test") do
        assert_not render_ga4_tag?
      end
    end
  end

  test "ga4 tag is disabled in production without measurement id" do
    with_env("GA4_MEASUREMENT_ID", nil) do
      with_rails_env("production") do
        assert_not render_ga4_tag?
      end
    end
  end

  test "google site verification is enabled only in production with token" do
    with_env("GOOGLE_SITE_VERIFICATION", "google-token") do
      with_rails_env("production") do
        assert render_google_site_verification?
        assert_equal "google-token", google_site_verification
      end
    end
  end

  test "google site verification is disabled outside production" do
    with_env("GOOGLE_SITE_VERIFICATION", "google-token") do
      with_rails_env("test") do
        assert_not render_google_site_verification?
      end
    end
  end

  test "google site verification is disabled without token" do
    with_env("GOOGLE_SITE_VERIFICATION", nil) do
      with_rails_env("production") do
        assert_not render_google_site_verification?
      end
    end
  end

  private

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end

  def with_rails_env(name)
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new(name) }
    yield
  ensure
    Rails.define_singleton_method(:env) { original.call }
  end
end
