module Aicoo
  module LpIntegration
    class ProductionVerifier
      Result = Data.define(:success, :message, :status, :url)

      def initialize(business:, fetcher: Aicoo::PublicHttpFetcher.new)
        @business = business
        @fetcher = fetcher
      end

      def call
        overview = Overview.new(business)
        raise ArgumentError, "本番URLを設定してください。" if overview.production_url.blank?
        raise ArgumentError, "LP作成元設定を保存してください。" unless overview.source_prototype

        response = fetcher.get(overview.production_url)
        stamp!(overview.source_prototype, {
          "last_verified_at" => Time.current.iso8601,
          "last_verification_status" => "success",
          "last_verified_url" => response.url,
          "last_error" => nil
        })
        Result.new(success: true, message: "本番URLへ接続できました。", status: response.status, url: response.url)
      rescue StandardError => e
        stamp_failure(e)
        Result.new(success: false, message: "本番確認に失敗しました: #{e.message}", status: nil, url: nil)
      end

      private

      attr_reader :business, :fetcher

      def stamp_failure(error)
        prototype = Overview.new(business).source_prototype
        return unless prototype

        stamp!(prototype, {
          "last_verification_status" => "failed",
          "last_error" => error.message.to_s.truncate(500)
        })
      end

      def stamp!(prototype, values)
        prototype.update!(metadata: prototype.metadata.to_h.merge(values))
      end
    end
  end
end
