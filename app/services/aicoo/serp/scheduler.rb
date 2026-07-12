module Aicoo
  module Serp
    class Scheduler
      DEFAULTS = {
        "scheduler_enabled" => false,
        "frequency" => "daily",
        "run_time" => "07:00",
        "daily_query_limit" => 30,
        "max_concurrency" => 1,
        "exploration_mode" => "ai_auto",
        "exploration_query" => "",
        "exploration_country" => "日本",
        "exploration_region" => "",
        "learning_enabled" => true,
        "new_field_ratio" => 70,
        "proven_field_ratio" => 30,
        "exclusion_rules" => %w[existing_businesses deleted_businesses duplicate_markets]
      }.freeze

      Result = Data.define(:status, :reason, :serp_run)

      def self.settings
        DEFAULTS.merge(DataSourceCostProfile.for_source("serp").metadata.to_h.fetch("scheduler", {}))
      end

      def self.update!(attributes)
        profile = DataSourceCostProfile.for_source("serp")
        profile.update!(
          metadata: profile.metadata.to_h.merge(
            "scheduler" => settings.merge(attributes.compact)
          )
        )
      end

      def self.enabled?
        ActiveModel::Type::Boolean.new.cast(settings["scheduler_enabled"])
      end

      def self.run!(executed_by: "scheduler", force: false)
        return Result.new("skipped", "scheduler_disabled", nil) unless enabled? || executed_by == "manual"
        return Result.new("skipped", "already_running", SerpRun.where(status: "running").recent.first) if SerpRun.where(status: "running").exists?

        serp_run = Aicoo::Serp::RunExecutor.new(executed_by:, force:).call
        Result.new(serp_run.status, nil, serp_run)
      end
    end
  end
end
