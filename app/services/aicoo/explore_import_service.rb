require "csv"
require "json"

module Aicoo
  class ExploreImportService
    Result = Data.define(:imported_count, :errors, :observations)
    PreviewObservation = Data.define(:title, :description, :score, :observation_type, :observed_at, :metadata)

    class << self
      def run!(source_type:, format:, raw_text:)
        new(source_type:, format:, raw_text:).run!
      end

      def preview(source_type:, format:, raw_text:)
        new(source_type:, format:, raw_text:).preview
      end
    end

    def initialize(source_type:, format:, raw_text:)
      @source_type = source_type.to_s
      @format = format.to_s
      @raw_text = raw_text.to_s
    end

    def preview
      Result.new(imported_count: 0, errors: errors, observations: parsed_observations)
    end

    def run!
      return Result.new(imported_count: 0, errors: errors, observations: []) if errors.any?

      previews = parsed_observations
      return Result.new(imported_count: 0, errors: errors, observations: []) if errors.any?

      observations = []
      ActiveRecord::Base.transaction do
        previews.each do |preview_observation|
          observations << data_source.explore_observations.create!(
            title: preview_observation.title,
            description: preview_observation.description,
            observation_type: preview_observation.observation_type,
            score: preview_observation.score,
            observed_at: preview_observation.observed_at,
            metadata: preview_observation.metadata
          )
        end
        ExploreImportLog.create!(
          source_type: source_type,
          import_format: format,
          imported_count: observations.size
        )
        data_source.update!(last_sync_at: Time.current, last_success_at: Time.current, status: "active")
      end

      Result.new(imported_count: observations.size, errors: [], observations:)
    end

    private

    attr_reader :source_type, :format, :raw_text

    def errors
      @errors ||= [].tap do |items|
        items << "source_type is invalid" unless ExploreDataSource::SOURCE_TYPES.include?(source_type)
        items << "format is invalid" unless ExploreImportLog::IMPORT_FORMATS.include?(format)
        items << "raw_text is blank" if raw_text.blank?
      end
    end

    def parsed_observations
      return [] if errors.any?

      @parsed_observations ||= case format
      when "csv"
        parse_csv
      when "json"
        parse_json
      else
        parse_text
      end
    rescue CSV::MalformedCSVError, JSON::ParserError => e
      errors << e.message
      []
    end

    def parse_csv
      CSV.parse(raw_text, headers: true).filter_map do |row|
        build_preview(row.to_h)
      end
    end

    def parse_json
      payload = JSON.parse(raw_text)
      Array.wrap(payload).filter_map do |entry|
        build_preview(entry)
      end
    end

    def parse_text
      raw_text.lines.map(&:strip).reject(&:blank?).map do |line|
        build_preview("title" => line)
      end
    end

    def build_preview(attributes)
      title = attributes["title"].presence || attributes[:title].presence
      return if title.blank?

      PreviewObservation.new(
        title: title,
        description: attributes["description"].presence || attributes[:description].presence,
        score: normalized_score(attributes["score"] || attributes[:score]),
        observation_type: normalized_observation_type(attributes["observation_type"].presence || attributes[:observation_type].presence),
        observed_at: parse_time(attributes["observed_at"] || attributes[:observed_at]),
        metadata: { "import_format" => format, "manual_import" => true }
      )
    end

    def normalized_score(value)
      score = value.presence || 50
      [ [ score.to_d, 0 ].max, 100 ].min
    end

    def normalized_observation_type(value)
      value.to_s.presence_in(ExploreObservation::OBSERVATION_TYPES) || "opportunity"
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : Time.current
    rescue ArgumentError
      Time.current
    end

    def data_source
      @data_source ||= ExploreDataSource.find_or_create_by!(source_type:) do |source|
        source.name = source_type.humanize
        source.enabled = true
        source.status = "active"
      end
    end
  end
end
