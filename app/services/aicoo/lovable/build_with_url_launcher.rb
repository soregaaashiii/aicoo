require "uri"

module Aicoo
  module Lovable
    class BuildWithUrlLauncher
      Result = Data.define(:url, :launcher_name, :prompt_length, :image_count)

      def initialize(configuration: Configuration.new)
        @configuration = configuration
      end

      def call(prompt:, image_urls: [])
        raise ArgumentError, "Lovable Promptが空です。" if prompt.blank?

        images = valid_image_urls(image_urls)
        Result.new(
          url: BuildUrl.call(prompt, images:, base_url: configuration.build_url),
          launcher_name: "build_with_url",
          prompt_length: prompt.to_s.length,
          image_count: images.length
        )
      end

      private

      attr_reader :configuration

      def valid_image_urls(values)
        Array(values).filter_map do |value|
          uri = URI.parse(value.to_s)
          value.to_s if uri.is_a?(URI::HTTP) && uri.host.present?
        rescue URI::InvalidURIError
          nil
        end.first(10)
      end
    end
  end
end
