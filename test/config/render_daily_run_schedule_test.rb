require "test_helper"
require "yaml"

class RenderDailyRunScheduleTest < ActiveSupport::TestCase
  test "Render Cron runs once daily at the default Japan time" do
    config = YAML.safe_load_file(Rails.root.join("render.yaml"), aliases: true)
    service = config.fetch("services").find { |row| row["type"] == "cron" && row["startCommand"] == "bundle exec rails aicoo:daily_run" }

    assert service
    assert_equal "0 23 * * *", service.fetch("schedule")

    minute, hour, day, month, weekday = service.fetch("schedule").split
    assert_equal [ "*", "*", "*" ], [ day, month, weekday ]
    assert_not_includes hour, ","

    utc_time = Time.utc(2026, 8, 1, hour.to_i, minute.to_i)
    japan_time = utc_time.in_time_zone("Asia/Tokyo")
    assert_equal [ 8, 0 ], [ japan_time.hour, japan_time.min ]
  end
end
