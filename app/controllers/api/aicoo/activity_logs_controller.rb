module Api
  module Aicoo
    class ActivityLogsController < ActionController::API
      before_action :authenticate_api_key!

      def create
        log_activity_api_received
        business = find_business
        unless business
          Rails.logger.warn("[Activity API] business found=false business_key=#{params[:business_key].presence || '(blank)'}")
          return render json: { ok: false, error: "business_not_found" }, status: :not_found
        end

        Rails.logger.info("[Activity API] business found=true business_id=#{business.id} business_name=#{business.name}")

        result = ::Aicoo::ActivityIngestor.ingest_payload(
          business:,
          payload: activity_log_attributes.merge(business_key: params[:business_key])
        )
        unless result.saved?
          Rails.logger.warn(
            "[Activity API] ActivityIngestor result=saved_false " \
            "business_id=#{business.id} error=#{result.error_message.presence || 'activity_log_not_created'}"
          )
          return render json: { ok: false, error: result.error_message.presence || "activity_log_not_created" }, status: :unprocessable_entity
        end

        activity_log = result.activity_log
        Rails.logger.info(
          "[Activity API] ActivityIngestor result=saved_true " \
          "BusinessActivityLog id=#{activity_log.id} business_id=#{business.id} " \
          "activity_type=#{activity_log.activity_type} resource=#{activity_log.resource_type}##{activity_log.resource_id}"
        )
        render json: {
          ok: true,
          id: activity_log.id,
          duplicate: !activity_log.previously_new_record?,
          evaluation_status: activity_log.evaluation_status
        }, status: activity_log.previously_new_record? ? :created : :ok
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn(
          "[Activity API] validation errors=#{e.record.errors.full_messages.to_sentence} " \
          "record=#{e.record.class.name}"
        )
        render json: { ok: false, error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error("[Activity API] failed #{e.class}: #{e.message}")
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      def authenticate_api_key!
        expected = ENV["AICOO_ACTIVITY_API_TOKEN"].presence ||
          ENV["AICOO_ACTIVITY_API_KEY"].presence ||
          ENV["AICOO_API_KEY"].presence
        authorization_present = request.headers["Authorization"].present? || request.headers["X-AICOO-API-Key"].present?
        token_valid = expected.present? && secure_compare(bearer_token, expected)
        Rails.logger.info(
          "[Activity API] Authorization present=#{authorization_present} " \
          "token #{token_valid ? 'valid' : 'invalid'} expected_configured=#{expected.present?}"
        )
        return if token_valid

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
        if business_id
          business = Business.real_businesses.find_by(id: business_id)
          Rails.logger.info("[Activity API] business lookup by id=#{business_id} found=#{business.present?}")
          return business
        end

        business_key = params[:business_key].presence
        Rails.logger.info("[Activity API] business_key=#{business_key.presence || '(blank)'}")
        return unless business_key

        business = Business.real_businesses.find_by(project_key: business_key) ||
          Business.real_businesses.find_by(name: business_key) ||
          SourceAppConnection.enabled.active.find_by(source_app: business_key)&.business ||
          business_alias_for(business_key)
        Rails.logger.info("[Activity API] business lookup by key=#{business_key} found=#{business.present?}")
        business
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

      def log_activity_api_received
        Rails.logger.info(
          "[Activity API] received business_key=#{params[:business_key].presence || '(blank)'} " \
          "source_type=#{params[:source_type].presence || params[:resource_type].presence || '(blank)'} " \
          "source_id=#{params[:source_id].presence || params[:resource_id].presence || '(blank)'}"
        )
      end
    end
  end
end
