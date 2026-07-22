module Aicoo
  module LpIntegration
    class GoogleMeasurementUpdater
      def initialize(business:, measurement_id:)
        @business = business
        @measurement_id = measurement_id.to_s.strip.presence
      end

      def call
        overview = Overview.new(business)
        prototype = overview.source_prototype
        return if prototype.nil? && measurement_id.nil?

        prototype ||= business.business_prototypes.new(
          prototype_type: "other",
          name: "LP作成元",
          location: "手動指定（未設定）",
          status: "active"
        )
        metadata = prototype.metadata.to_h.merge(
          "role" => Overview::ROLE,
          "lp_source_type" => prototype.metadata.to_h["lp_source_type"].presence || "manual",
          "ga4_measurement_id" => measurement_id,
          "updated_by" => "owner",
          "updated_at" => Time.current.iso8601
        )
        prototype.update!(metadata:)
        prototype
      end

      private

      attr_reader :business, :measurement_id
    end
  end
end
