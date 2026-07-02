module Aicoo
  module Serp
    class CandidatePromoter
      Result = Data.define(:keyword, :serp_query, :status)
      Summary = Data.define(:results) do
        def created_count
          results.count { |result| result.status == "created" }
        end

        def updated_count
          results.count { |result| result.status == "updated" }
        end

        def skipped_count
          results.count { |result| result.status == "skipped" }
        end

        def promoted_count
          created_count + updated_count
        end

        def serp_queries
          results.map(&:serp_query).compact
        end
      end

      def self.promote!(keywords)
        new(Array(keywords)).call
      end

      def initialize(keywords)
        @keywords = keywords
      end

      def call
        Summary.new(results: keywords.map { |keyword| promote_one!(keyword) })
      end

      private

      attr_reader :keywords

      def promote_one!(keyword)
        keyword.with_lock do
          normalized_query = SerpQuery.normalize(keyword.keyword)
          return Result.new(keyword:, serp_query: nil, status: "skipped") if normalized_query.blank?

          serp_query = keyword.business.serp_queries.find_or_initialize_by(normalized_query:)
          status = serp_query.persisted? ? "updated" : "created"
          serp_query.assign_attributes(
            query: keyword.keyword,
            category: serp_query.category.presence || "existing_business",
            enabled: true,
            status: "active",
            priority: keyword.priority_score.to_i,
            country: serp_query.country.presence || "jp",
            language: serp_query.language.presence || "ja",
            daily_limit: serp_query.daily_limit.to_i.positive? ? serp_query.daily_limit : 1,
            metadata: serp_query.metadata.to_h.merge(
              "source" => keyword.source.presence || "ai_suggested",
              "business_serp_keyword_id" => keyword.id,
              "promoted_from" => "business_serp_keyword",
              "promoted_at" => Time.current.iso8601
            )
          )
          serp_query.save!
          keyword.update!(
            status: "active",
            metadata_json: keyword.metadata_json.to_h.merge(
              "serp_query_id" => serp_query.id,
              "promoted_to_serp_query_at" => Time.current.iso8601
            )
          )
          Result.new(keyword:, serp_query:, status:)
        end
      end
    end
  end
end
