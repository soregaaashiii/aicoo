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
        :service_created_count,
        :skipped_count,
        :failed_count,
        :business_ids,
        :landing_page_ids,
        :business_service_ids,
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
        Aicoo::MemoryDiagnostics.measure("Aicoo::Serp::AutoNewBusinessPublisher#call", context: memory_context) do
          counters = Hash.new(0)
          business_ids = []
          landing_page_ids = []
          business_service_ids = []
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

            unless auto_publishable?(candidate)
              mark_quality_review_required!(candidate)
              counters[:skipped_count] += 1
              next
            end

            created_business = false
            created_landing_page = false
            created_service = false
            business = nil
            landing_page = nil
            business_service = nil

            ActiveRecord::Base.transaction do
              promotion = Aicoo::ActionCandidateBusinessPromoter.new(candidate).call
              business = promotion.business
              created_business = promotion.created

              prepare_business!(business) if created_business || auto_created_business?(business)

              if launch_asset_type(candidate) == "saas"
                before_service_id = business.business_services.order(updated_at: :desc).first&.id
                business_service = ensure_business_service!(business, nil, candidate)
                created_service = business_service.id != before_service_id
              else
                before_lp_id = business.aicoo_lab_landing_pages.order(updated_at: :desc).first&.id
                landing_page = Aicoo::Owner::NewBusinessLandingPageBuilder.new(candidate).call
                created_landing_page = landing_page.id != before_lp_id
              end

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
                    "created_asset_type" => launch_asset_type(candidate),
                    "landing_page_id" => landing_page&.id,
                    "business_service_id" => business_service&.id,
                    "service_url" => business_service&.url,
                    "draft_slug" => landing_page&.published_slug,
                    "draft_created" => landing_page.present?,
                    "completed_at" => Time.current.iso8601
                  }.compact
                )
              )
            end

            counters[:business_created_count] += 1 if created_business
            counters[:business_linked_count] += 1 unless created_business
            counters[:lp_created_count] += 1 if created_landing_page
            counters[:lp_published_count] += 1 if landing_page
            counters[:service_created_count] += 1 if created_service
            business_ids << business.id
            landing_page_ids << landing_page.id if landing_page
            business_service_ids << business_service.id if business_service
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
            service_created_count: counters[:service_created_count],
            skipped_count: counters[:skipped_count],
            failed_count: counters[:failed_count],
            business_ids: business_ids.uniq,
            landing_page_ids: landing_page_ids.uniq,
            business_service_ids: business_service_ids.uniq,
            errors:
          )
        end
      end

      private

      attr_reader :serp_run, :candidates, :limit, :source

      def memory_context(extra = {})
        {
          serp_run_id: serp_run&.id,
          candidate_count: candidates ? Array(candidates).size : nil,
          limit:,
          source:
        }.merge(extra).compact
      end

      def candidate_scope
        base = if candidates
          ActionCandidate.where(id: Array(candidates).map(&:id))
        else
          ActionCandidate.where(nil)
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

      def auto_publishable?(candidate)
        metadata = candidate.metadata.to_h
        return false if metadata["manual_approval_required"] && source != "owner_new_business_pipeline"

        quality = metadata["business_idea_quality"].to_h
        return true if quality["auto_publishable"] == true

        refreshed = quality_for(candidate)
        candidate.update_columns(
          metadata: metadata.merge(
            "business_idea_quality" => refreshed.to_h,
            "requires_human_edit" => !refreshed.auto_publishable,
            "auto_business_publish_required" => refreshed.auto_publishable
          ),
          updated_at: Time.current
        ) if quality.blank? || quality != refreshed.to_h

        refreshed.auto_publishable
      end

      def quality_for(candidate)
        metadata = candidate.metadata.to_h
        Aicoo::Serp::BusinessIdeaQualityJudge.call(
          attributes: {
            "business_name" => metadata["business_name"].presence || metadata["service_name"].presence || candidate.title,
            "target_customer" => metadata["target_customer"].presence || metadata["customer"].presence || metadata["target_user"],
            "problem" => metadata["problem"],
            "offering" => metadata["offering"].presence || metadata["solution"].presence || metadata["provided_service"],
            "revenue_model" => metadata["revenue_model"].presence || metadata["monetization"],
            "validation_method" => metadata["validation_method"].presence || metadata["validation_plan"].presence || metadata["validation_step"],
            "product_type" => metadata["product_type"].presence || metadata["launch_asset_type"].presence || metadata["lp_or_saas"]
          },
          source_query: metadata["source_query"]
        )
      end

      def mark_quality_review_required!(candidate)
        candidate.update_columns(
          status: "planning",
          metadata: candidate.metadata.to_h.merge(
            "requires_human_edit" => true,
            "manual_approval_required" => true,
            "auto_business_publish_required" => false,
            "auto_new_business_publication" => {
              "completed" => false,
              "skipped" => true,
              "reason" => "business_idea_quality_needs_edit",
              "skipped_at" => Time.current.iso8601
            }
          ),
          updated_at: Time.current
        )
      end

      def launch_asset_type(candidate)
        value = candidate.metadata.to_h["launch_asset_type"].presence ||
                candidate.metadata.to_h["lp_or_saas"].presence ||
                candidate.metadata.to_h["validation_asset_type"].presence
        value.to_s == "saas" ? "saas" : "lp"
      end

      def already_published?(candidate)
        metadata = candidate.metadata.to_h["auto_new_business_publication"].to_h
        business_id = metadata["business_id"].presence || candidate.business_id
        landing_page_id = metadata["landing_page_id"]

        return false if business_id.blank?

        business = Business.real_businesses.find_by(id: business_id)
        return false unless business
        return true if metadata["completed"] == true && metadata["created_asset_type"] == "saas" &&
                       metadata["business_service_id"].present? &&
                       business.business_services.exists?(id: metadata["business_service_id"])

        if landing_page_id.present?
          return AicooLabLandingPage.exists?(id: landing_page_id, business_id: business.id)
        end

        business.aicoo_lab_landing_pages.exists?
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
          new_lp_auto_deploy_enabled: false,
          lifecycle_stage: "lp_validation",
          resource_status: "active",
          business_type: "landing_page",
          source: business.source.presence || "serp",
          metadata: business.metadata.to_h.merge(
            "auto_serp_business" => true,
            "auto_lp_published" => false,
            "auto_draft_created" => true,
            "business_flow" => "serp_auto_added",
            "auto_draft_created_at" => Time.current.iso8601
          )
        )
        Aicoo::NewBusinessAutomationDefaults.apply!(business)
        business.update!(
          auto_build_enabled: false,
          new_lp_auto_deploy_enabled: false,
          metadata: business.metadata.to_h.merge(
            "serp_auto_business_scope" => "draft_only",
            "codex_auto_submit_default" => false
          )
        )
      end

      def ensure_business_service!(business, landing_page, candidate)
        raise ArgumentError, "削除済みBusinessにはServiceを作成できません。" if business.deleted?

        service_name = "#{business.name} SaaS"
        service_kind = launch_asset_type(candidate) == "saas" ? "saas_spec_draft" : "saas_mvp_foundation"
        service = business.business_services.find_by("metadata ->> 'service_kind' = ?", service_kind) ||
                  business.business_services.find_or_initialize_by(name: service_name)

        service.assign_attributes(
          name: service.name.presence || service_name,
          url: service.url.presence,
          domain: nil,
          deploy_target: service_kind,
          status: service.status.presence == "production" ? "production" : "planning",
          metadata: service.metadata.to_h.merge(
            "auto_created" => true,
            "service_kind" => service_kind,
            "source" => source,
            "source_action_candidate_id" => candidate.id,
            "validation_landing_page_id" => landing_page&.id,
            "validation_lp_slug" => landing_page&.published_slug,
            "public_url" => service.url.presence,
            "spec_draft" => saas_spec_draft_for(candidate),
            "minimum_features" => [
              "ユーザーの課題登録フォーム",
              "登録内容のAICOO Activity Logging",
              "Ownerが反応を確認してMVP改善へ進める導線"
            ],
            "created_by_service" => "Aicoo::Serp::AutoNewBusinessPublisher",
            "updated_at" => Time.current.iso8601
          )
        )
        service.save!
        if service_kind != "saas_spec_draft"
          service_url = "/mvp/#{service.id}"
          service.update!(
            url: service_url,
            metadata: service.metadata.to_h.merge("public_url" => service_url)
          ) if service.url != service_url
        end
        service
      end

      def saas_spec_draft_for(candidate)
        metadata = candidate.metadata.to_h
        {
          "business_name" => metadata["business_name"].presence || candidate.title,
          "target_customer" => metadata["target_customer"],
          "problem" => metadata["problem"],
          "offering" => metadata["offering"].presence || metadata["solution"],
          "value_proposition" => metadata["value_proposition"].presence || metadata["differentiation"],
          "revenue_model" => metadata["revenue_model"].presence || metadata["monetization"],
          "validation_method" => metadata["validation_method"].presence || metadata["validation_plan"].presence || metadata["validation_step"],
          "mvp_scope" => [
            "課題登録",
            "相談内容の管理",
            "Ownerへの通知",
            "反応データのAICOO Activity Logging"
          ],
          "created_at" => Time.current.iso8601
        }.compact
      end

      def auto_created_business?(business)
        business&.metadata.to_h["created_from"] == "action_candidate" &&
          business.metadata.to_h["candidate_kind"] == "new_business"
      end
    end
  end
end
