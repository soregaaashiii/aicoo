# 吸えログ Activity Logging 連携

吸えログで店舗・記事の作成/更新/削除が発生したら、AICOOのActivity APIへ送信します。
送信に失敗しても吸えログ側の保存処理は止めません。

## AICOO側ENV

```bash
AICOO_ACTIVITY_API_TOKEN=共有トークン
```

## 吸えログ側ENV

```bash
AICOO_API_URL=https://aicoo.onrender.com
AICOO_ACTIVITY_API_TOKEN=共有トークン
AICOO_BUSINESS_KEY=suelog
AICOO_ACTIVITY_LOGGING_ENABLED=true
```

## 吸えログ側サービス

`app/services/aicoo_activity_logger.rb` を追加します。

```ruby
require "net/http"
require "uri"

class AicooActivityLogger
  class << self
    def log(**attributes)
      new.log(**attributes)
    end
  end

  def log(**attributes)
    return { ok: true, skipped: true, reason: "disabled" } if ENV["AICOO_ACTIVITY_LOGGING_ENABLED"].to_s == "false"

    payload = build_payload(attributes)
    response = post_payload(payload)
    return { ok: true, status: response.code.to_i } if response.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("[AicooActivityLogger] failed HTTP #{response.code}: #{response.body}")
    { ok: false, error: "HTTP #{response.code}" }
  rescue StandardError => e
    Rails.logger.warn("[AicooActivityLogger] failed #{e.class}: #{e.message}")
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  private

  def build_payload(attributes)
    attrs = attributes.symbolize_keys
    {
      business_key: attrs[:business_key] || ENV.fetch("AICOO_BUSINESS_KEY", "suelog"),
      activity_type: attrs[:activity_type],
      source_type: attrs[:source_type],
      source_id: attrs[:source_id],
      title: attrs[:title],
      summary: attrs[:summary],
      occurred_at: attrs[:occurred_at] || Time.current.iso8601,
      metadata: attrs[:metadata] || {}
    }.compact
  end

  def post_payload(payload)
    uri = URI.join(ENV.fetch("AICOO_API_URL"), "/api/aicoo/activity_logs")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch("AICOO_ACTIVITY_API_TOKEN")}"
    request.body = payload.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end
end
```

## Shop callback例

`app/models/shop.rb` に追加します。

```ruby
after_commit :log_aicoo_shop_created, on: :create
after_commit :log_aicoo_shop_updated, on: :update
after_commit :log_aicoo_shop_destroyed, on: :destroy
after_discard :log_aicoo_shop_discarded if respond_to?(:after_discard)

private

def log_aicoo_shop_created
  log_aicoo_shop_activity("data_added", "店舗を追加")
end

def log_aicoo_shop_updated
  return if previous_changes.except("updated_at").blank?

  log_aicoo_shop_activity("data_updated", "店舗を更新")
end

def log_aicoo_shop_destroyed
  log_aicoo_shop_activity("data_deleted", "店舗を削除")
end

def log_aicoo_shop_discarded
  log_aicoo_shop_activity("data_unpublished", "店舗を非公開")
end

def log_aicoo_shop_activity(activity_type, title)
  AicooActivityLogger.log(
    business_key: "suelog",
    activity_type:,
    source_type: "shop",
    source_id: id,
    title: "#{title}: #{name}",
    summary: "#{name} の店舗情報を変更しました",
    occurred_at: Time.current.iso8601,
    metadata: {
      area: try(:area),
      smoking_status: try(:smoking_status),
      station: try(:station),
      source: try(:source),
      tabelog_url: try(:tabelog_url),
      changed_fields: previous_changes.except("updated_at").keys
    }.compact
  )
end
```

## Article callback例

`app/models/article.rb` に追加します。

```ruby
after_commit :log_aicoo_article_created, on: :create
after_commit :log_aicoo_article_updated, on: :update
after_commit :log_aicoo_article_destroyed, on: :destroy

private

def log_aicoo_article_created
  log_aicoo_article_activity("article_created", "記事を追加")
end

def log_aicoo_article_updated
  return if previous_changes.except("updated_at").blank?

  log_aicoo_article_activity("article_updated", "記事を更新")
end

def log_aicoo_article_destroyed
  log_aicoo_article_activity("article_deleted", "記事を削除")
end

def log_aicoo_article_activity(activity_type, title)
  AicooActivityLogger.log(
    business_key: "suelog",
    activity_type:,
    source_type: "article",
    source_id: id,
    title: "#{title}: #{try(:title)}",
    summary: "#{try(:title)} の記事情報を変更しました",
    occurred_at: Time.current.iso8601,
    metadata: {
      slug: try(:slug),
      area: try(:area),
      target_keyword: try(:target_keyword),
      changed_fields: previous_changes.except("updated_at").keys
    }.compact
  )
end
```

## 確認

吸えログでShopを1件追加した後、AICOOで確認します。

```bash
bin/rails runner 'puts BusinessActivityLog.where(source_app: "suelog").order(created_at: :desc).limit(5).pluck(:id, :activity_type, :resource_type, :resource_id, :title).inspect'
```

画面:

```text
/admin/business_activity_logs
/admin/activity_learning_e2e_check
```
