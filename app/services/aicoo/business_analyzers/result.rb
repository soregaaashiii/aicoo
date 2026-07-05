module Aicoo
  module BusinessAnalyzers
    Result = Data.define(:business, :analyzer, :created, :skipped, :issues, :opportunities, :handled) do
      def created_count
        created.size
      end

      def skipped_count
        skipped.size
      end

      def handled?
        handled == true
      end

      def diagnostics
        {
          "business_id" => business&.id,
          "business_name" => business&.name,
          "business_type" => business&.business_type,
          "analyzer" => analyzer,
          "created_count" => created_count,
          "skipped_count" => skipped_count,
          "issue_count" => issues.size,
          "opportunity_count" => opportunities.size,
          "skipped_reasons" => skipped
        }
      end
    end
  end
end
