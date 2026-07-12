module Aicoo
  module Serp
    class AutoNewBusinessPublisher
      BLOCKING_DELETION_REASONS = %w[
        SERP誤生成
        既存事業との重複
      ].freeze

      Result = Data.define(
        :checked_count,
        :business_created_count,
        :business_linked_count,
        :lp_created_count,
        :lp_published_count,
        :skipped_count,
        :failed_count,
        :business_ids,
        :landing_page_ids,
        :errors
      )

      def self.call(...)
        new(...).call
      end

      def initialize(serp_run: nil, candidates: nil, limit: 50, source: "serp_auto_new_business_publisher")
        @serp_run = serp_run
        @candidates = candidates
        @limit = limit
        @source = source
      end

      def call
        counters = Hash.new(0)
        business_ids = []
        landing_page_ids = []
        errors = []

        candidate_scope.find_each do |candidate|
          counters[:checked_count] += 1

          if already_published?(candidate)
            counters[:skipped_count] += 1
            next
          end

          if republish_blocked?(candidate)
            counters[:skipped_count] += 1
            next
          end

          created_business = false
          created_landing_page = false
          business = nil
          landing_page = nil

          ActiveRecord::Base.transaction do
            promotion = Aicoo::ActionCandidateBusinessPromoter.new(candidate).call
            business = promotion.business
            created_business = promotion.created

            prepare_business!(business) if created_business || auto_created_business?(business)

            before_lp_id = business.aicoo_lab_landing_pages.order(updated_at: :desc).first&.id
            landing_page = Aicoo::Owner::NewBusinessLandingPageBuilder.new(candidate).call
            created_landing_page = landing_page.id != before_lp_id
            landing_page.publish! unless landing_page.publicly_visible?

            candidate.update!(
              status: "done",
              approved_at: candidate.approved_at || Time.current,
              approved_by: candidate.approved_by.presence || "system",
              metadata: candidate.metadata.to_h.merge(
                "auto_new_business_publication" => {
                  "completed" => true,
                  "source" => source,
                  "serp_run_id" => serp_run&.id,
                  "business_id" => business.id,
                  "landing_page_id" => landing_page.id,
                  "published_slug" => landing_page.published_slug,
                  "published_at" => landing_page.published_at&.iso8601,
                  "completed_at" => Time.current.iso8601
                }
              )
            )
          end

          counters[:business_created_count] += 1 if created_business
          counters[:business_linked_count] += 1 unless created_business
          counters[:lp_created_count] += 1 if created_landing_page
          counters[:lp_published_count] += 1
          business_ids << business.id
          landing_page_ids << landing_page.id
        rescue StandardError => e
          counters[:failed_count] += 1
          errors << {
            action_candidate_id: candidate.id,
            error_class: e.class.name,
            message: e.message
          }
          Rails.logger.warn(
            "[SERP AutoNewBusinessPublisher] failed action_candidate_id=#{candidate.id} #{e.class}: #{e.message}"
          )
        end

        Result.new(
          checked_count: counters[:checked_count],
          business_created_count: counters[:business_created_count],
          business_linked_count: counters[:business_linked_count],
          lp_created_count: counters[:lp_created_count],
          lp_published_count: counters[:lp_published_count],
          skipped_count: counters[:skipped_count],
          failed_count: counters[:failed_count],
          business_ids: business_ids.uniq,
          landing_page_ids: landing_page_ids.uniq,
          errors:
        )
      end

      private

      attr_reader :serp_run, :candidates, :limit, :source

      def candidate_scope
        base = if candidates
          ActionCandidate.where(id: Array(candidates).map(&:id))
        else
          ActionCandidate.all
        end

        base = base.where.not(status: %w[rejected archived])
                   .where(generation_source: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_SOURCES)
                   .where(
                     "department = :department OR metadata ->> 'candidate_kind' = :candidate_kind OR action_type IN (:action_types)",
                     department: "new_business",
                     candidate_kind: "new_business",
                     action_types: Aicoo::ActionCandidateBusinessPromoter::NEW_BUSINESS_ACTION_TYPES
                   )

        if serp_run
          base = base.where("metadata ->> 'serp_run_id' = ?", serp_run.id.to_s)
        end

        base.order(Arel.sql("final_score DESC NULLS LAST, expected_hourly_value_yen DESC NULLS LAST, created_at ASC")).limit(limit)
      end

      def already_published?(candidate)
        metadata = candidate.metadata.to_h["auto_new_business_publication"].to_h
        business_id = metadata["business_id"].presence || candidate.business_id
        landing_page_id = metadata["landing_page_id"]

        return false if business_id.blank?

        business = Business.real_businesses.find_by(id: business_id)
        return false unless business

        if landing_page_id.present?
          return AicooLabLandingPage.publicly_available.exists?(id: landing_page_id, business_id: business.id)
        end

        business.aicoo_lab_landing_pages.publicly_available.exists?
      end

      def republish_blocked?(candidate)
        metadata = candidate.metadata.to_h
        return mark_republish_blocked!(candidate, reason: metadata["deletion_reason"].presence || "blocked_by_candidate") if metadata["do_not_recreate"] || metadata["auto_republish_blocked"]

        if candidate.business&.deleted?
          return mark_republish_blocked!(candidate, reason: candidate.business.deletion_reason.presence || "business_deleted")
        end

        deleted_business = deleted_business_for(candidate)
        return false unless deleted_business

        mark_republish_blocked!(candidate, reason: deleted_business.deletion_reason.presence || "deleted_business_match", deleted_business:)
      end

      def deleted_business_for(candidate)
        metadata = candidate.metadata.to_h
        business_id = metadata.dig("auto_new_business_publication", "business_id").presence ||
                      metadata.dig("business_promotion", "business_id").presence ||
                      metadata["deleted_business_id"].presence ||
                      candidate.business_id
        if business_id.present?
          business = Business.deleted.find_by(id: business_id)
          return business if business
        end

        fingerprint = metadata["discovery_fingerprint"].presence || metadata["fingerprint"].presence
        if fingerprint
          business = Business.deleted.find_by("metadata ->> 'discovery_fingerprint' = ?", fingerprint)
          return business if business
        end

        name = metadata["business_name"].presence || metadata["service_name"].presence || candidate.title.to_s
        return if name.blank?

        Business.deleted.where("LOWER(name) = ?", name.squish.downcase)
                .where(deletion_reason: BLOCKING_DELETION_REASONS)
                .first
      end

      def mark_republish_blocked!(candidate, reason:, deleted_business: nil)
        candidate.update_columns(
          metadata: candidate.metadata.to_h.merge(
            "auto_republish_blocked" => true,
            "do_not_recreate" => true,
            "business_deleted_at" => deleted_business&.deleted_at&.iso8601 || candidate.metadata.to_h["business_deleted_at"],
            "deleted_business_id" => deleted_business&.id || candidate.metadata.to_h["deleted_business_id"],
            "deletion_reason" => reason
          ).compact,
          updated_at: Time.current
        )
        true
      end

      def prepare_business!(business)
        raise ArgumentError, "削除済みBusinessは自動公開できません。" if business.deleted?

        business.update!(
          status: "exploring",
          launched: false,
          created_by_aicoo: true,
          daily_run_enabled: true,
          serp_enabled: true,
          auto_revision_mode: "automatic",
          auto_deploy_mode: "approval",
          auto_build_enabled: true,
          auto_build_requires_approval: false,
          auto_build_risk_level: "low",
          new_lp_auto_deploy_enabled: true,
          lifecycle_stage: "lp_validation",
          resource_status: "active",
          business_type: "landing_page",
          source: business.source.presence || "serp",
          metadata: business.metadata.to_h.merge(
            "auto_serp_business" => true,
            "auto_lp_published" => true,
            "business_flow" => "serp_auto_added",
            "auto_published_at" => Time.current.iso8601
          )
        )
        Aicoo::NewBusinessAutomationDefaults.apply!(business)
      end

      def auto_created_business?(business)
        business&.metadata.to_h["created_from"] == "action_candidate" &&
          business.metadata.to_h["candidate_kind"] == "new_business"
      end
    end
  end
end
