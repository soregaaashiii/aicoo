require "test_helper"

module Aicoo
  class BusinessTimelineTest < ActiveSupport::TestCase
    test "builds timeline from business related records" do
      business = businesses(:suelog)
      business.business_services.create!(name: "Suelog Service", status: "live")
      business.business_activity_logs.create!(
        source_app: "suelog",
        activity_type: "article_updated",
        resource_type: "Article",
        resource_id: "1",
        title: "記事更新",
        occurred_at: Time.current,
        detected_at: Time.current,
        idempotency_key: "timeline-article-updated"
      )

      items = BusinessTimeline.new(business).call

      assert items.any? { |item| item.title == "Idea作成" }
      assert items.any? { |item| item.title == "Service登録" }
      assert items.any? { |item| item.title == "Activity検知" }
    end
  end
end
