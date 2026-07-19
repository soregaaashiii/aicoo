module Aicoo
  class ActionCandidateCompletionContext
    def self.call(candidate)
      new(candidate).call
    end

    def initialize(candidate)
      @candidate = candidate
      @metadata = candidate.metadata.to_h.deep_stringify_keys
    end

    def call
      articles = article_records
      shops = shop_records
      {
        "registered_count" => nil,
        "area" => first_present(record_values(shops + articles, %w[area area_name city recommended_areas]), metadata_value(%w[area area_name city])),
        "station" => first_present(record_values(shops + articles, %w[station station_name nearest_station]), metadata_value(%w[station station_name nearest_station])),
        "genre" => first_present(record_values(shops + articles, %w[genre genre_name category category_name]), metadata_value(%w[genre genre_name category])),
        "smoking_type" => first_present(record_values(shops + articles, %w[smoking_type smoking_status smoking_area]), metadata_value(%w[smoking_type smoking_status smoking_area])),
        "target_shop_ids" => shops.map(&:id),
        "target_article_ids" => articles.map(&:id),
        "target_shop_count" => shops.size,
        "target_article_count" => articles.size,
        "context_source" => (articles.any? || shops.any?) ? "business_database" : "candidate_metadata"
      }
    end

    private

    attr_reader :candidate, :metadata

    def article_records
      return [] unless defined?(::Suelog::Article)

      keys = %w[article_id target_article_id source_article_id article_ids target_article_ids]
      keys << "target_record_id" if candidate.action_type.to_s.match?(/article|seo/)
      ids = resource_ids(keys)
      ::Suelog::Article.where(id: ids).to_a
    rescue StandardError => e
      Rails.logger.warn("[ActionCandidateLearning] article context unavailable candidate_id=#{candidate.id} error=#{e.class}: #{e.message}")
      []
    end

    def shop_records
      return [] unless defined?(::Suelog::Shop)

      keys = %w[shop_id target_shop_id source_shop_id shop_ids target_shop_ids]
      keys << "target_record_id" if candidate.action_type.to_s.match?(/shop|smoking/)
      ids = resource_ids(keys)
      ::Suelog::Shop.where(id: ids).to_a
    rescue StandardError => e
      Rails.logger.warn("[ActionCandidateLearning] shop context unavailable candidate_id=#{candidate.id} error=#{e.class}: #{e.message}")
      []
    end

    def resource_ids(keys)
      values = []
      each_pair(metadata) do |key, value|
        next unless key.in?(keys)

        values.concat(Array(value))
      end
      values.filter_map { |value| value.to_s if value.to_s.match?(/\A\d+\z/) }.uniq
    end

    def metadata_value(keys)
      each_pair(metadata) do |key, value|
        return value if key.in?(keys) && value.present? && !value.is_a?(Hash) && !value.is_a?(Array)
      end
      nil
    end

    def each_pair(value, &block)
      case value
      when Hash
        value.each do |key, child|
          yield key.to_s, child
          each_pair(child, &block)
        end
      when Array
        value.each { |child| each_pair(child, &block) }
      end
    end

    def record_values(records, columns)
      records.filter_map do |record|
        column = columns.find { |name| record.respond_to?(name) && record.public_send(name).present? }
        record.public_send(column) if column
      end.uniq.presence
    end

    def first_present(*values)
      values.find(&:present?)
    end
  end
end
