module Aicoo
  module ExternalSources
    class SuelogHealthCheck
      Result = Data.define(
        :status,
        :code,
        :message,
        :shops_count,
        :articles_count,
        :shop_clicks_count,
        :last_checked_at,
        :last_shop_updated_at,
        :last_article_updated_at,
        :last_shop_click_at,
        :error_class
      ) do
        def success?
          status == "success"
        end

        def warning?
          status == "warning"
        end

        def diagnostics
          {
            status:,
            code:,
            message:,
            shops_count:,
            articles_count:,
            shop_clicks_count:,
            last_checked_at:,
            last_shop_updated_at:,
            last_article_updated_at:,
            last_shop_click_at:,
            error_class:
          }.compact
        end
      end

      def self.call
        new.call
      end

      def call
        return warning("missing_database_url", "SUELOG_DATABASE_URL is not configured") unless SuelogRecord.configured?

        SuelogRecord.ensure_connection!
        Result.new(
          status: "success",
          code: "connected",
          message: "connected",
          shops_count: Suelog::Shop.limit(1_000_000_000).count,
          articles_count: Suelog::Article.limit(1_000_000_000).count,
          shop_clicks_count: Suelog::ShopClick.where(created_at: 30.days.ago..Time.current).count,
          last_checked_at: Time.current,
          last_shop_updated_at: Suelog::Shop.maximum(:updated_at),
          last_article_updated_at: Suelog::Article.maximum(:updated_at),
          last_shop_click_at: Suelog::ShopClick.maximum(:created_at),
          error_class: nil
        )
      rescue SuelogRecord::MissingDatabaseUrl
        warning("missing_database_url", "SUELOG_DATABASE_URL is not configured")
      rescue ActiveRecord::StatementInvalid => e
        warning(classify_statement_error(e), safe_message_for(e), e.class.name)
      rescue ActiveRecord::ConnectionNotEstablished, PG::Error => e
        warning("connection_failed", safe_message_for(e), e.class.name)
      rescue StandardError => e
        warning("connection_failed", safe_message_for(e), e.class.name)
      end

      private

      def warning(code, message, error_class = nil)
        Result.new(
          status: "warning",
          code:,
          message:,
          shops_count: nil,
          articles_count: nil,
          shop_clicks_count: nil,
          last_checked_at: Time.current,
          last_shop_updated_at: nil,
          last_article_updated_at: nil,
          last_shop_click_at: nil,
          error_class:
        )
      end

      def classify_statement_error(error)
        message = error.message.to_s
        return "relation_missing" if message.match?(/relation .* does not exist/i)
        return "schema_mismatch" if message.match?(/column .* does not exist/i)
        return "query_timeout" if message.match?(/statement timeout|canceling statement/i)

        "connection_failed"
      end

      def safe_message_for(error)
        message = error.message.to_s
        return "schema mismatch" if message.match?(/column .* does not exist/i)
        return "relation missing" if message.match?(/relation .* does not exist/i)
        return "query timeout" if message.match?(/statement timeout|canceling statement/i)

        "external suelog database is unavailable"
      end
    end
  end
end
