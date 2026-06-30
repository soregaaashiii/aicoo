module Api
  module Aicoo
    class ActivityLogsController < ActionController::API
      before_action :authenticate_api_key!

      def create
        business = find_business
        return render json: { ok: false, error: "business_not_found" }, status: :not_found unless business

        result = ::Aicoo::ActivityIngestor.ingest_payload(
          business:,
          payload: activity_log_attributes.merge(business_key: params[:business_key])
        )
        return render json: { ok: false, error: result.error_message.presence || "activity_log_not_created" }, status: :unprocessable_entity unless result.saved?

        activity_log = result.activity_log
        render json: {
          ok: true,
          id: activity_log.id,
          duplicate: !activity_log.previously_new_record?,
          evaluation_status: activity_log.evaluation_status
        }, status: activity_log.previously_new_record? ? :created : :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error("Activity log API failed: #{e.class}: #{e.message}")
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      def authenticate_api_key!
        expected = ENV["AICOO_ACTIVITY_API_TOKEN"].presence ||
          ENV["AICOO_ACTIVITY_API_KEY"].presence ||
          ENV["AICOO_API_KEY"].presence
        return if expected.present? && secure_compare(bearer_token, expected)

        render json: { ok: false, error: "unauthorized" }, status: :unauthorized
      end

      def secure_compare(value, expected)
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(value.to_s),
          Digest::SHA256.hexdigest(expected.to_s)
        )
      end

      def bearer_token
        authorization = request.headers["Authorization"].to_s
        return authorization.delete_prefix("Bearer ").strip if authorization.start_with?("Bearer ")

        request.headers["X-AICOO-API-Key"].to_s
      end

      def find_business
        business_id = params[:business_id].presence
        return Business.real_businesses.find_by(id: business_id) if business_id

        business_key = params[:business_key].presence
        return unless business_key

        Business.real_businesses.find_by(project_key: business_key) ||
          Business.real_businesses.find_by(name: business_key) ||
          SourceAppConnection.enabled.active.find_by(source_app: business_key)&.business ||
          business_alias_for(business_key)
      end

      def business_alias_for(business_key)
        case business_key.to_s
        when "suelog", "sue-log", "吸えログ"
          SourceAppConnection.ensure_suelog_defaults!
          Business.real_businesses.find_by(name: "吸えログ")
        end
      end

      def activity_log_attributes
        params.permit(
          :business_key,
          :source_app,
          :activity_type,
          :source_type,
          :source_id,
          :resource_type,
          :resource_id,
          :title,
          :summary,
          :occurred_at,
          :detected_at,
          :diff_summary,
          :estimated_work_seconds,
          :idempotency_key,
          changed_fields: {},
          before_snapshot: {},
          after_snapshot: {},
          metadata: {}
        ).to_h.symbolize_keys
      end
    end
  end
end
