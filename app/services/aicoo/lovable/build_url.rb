require "uri"

module Aicoo
  module Lovable
    class BuildUrl
      MAX_PROMPT_LENGTH = 50_000

      def self.call(prompt, images: [], base_url: Configuration.new.build_url)
        uri = URI(base_url)
        params = URI.decode_www_form(uri.query.to_s)
        params.reject! { |key, _value| key == "autosubmit" }
        params << [ "autosubmit", "true" ]
        uri.query = URI.encode_www_form(params)
        source_prompt = prompt.to_s.dup
        source_prompt.force_encoding(Encoding::UTF_8) if source_prompt.encoding == Encoding::BINARY
        normalized_prompt = source_prompt.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
        fragment_params = [ [ "prompt", normalized_prompt.each_char.take(MAX_PROMPT_LENGTH).join ] ]
        Array(images).compact_blank.first(10).each { |image_url| fragment_params << [ "images", image_url ] }
        uri.fragment = fragment_params.map do |key, value|
          "#{key}=#{URI.encode_www_form_component(value).gsub('+', '%20')}"
        end.join("&")
        uri.to_s
      end
    end
  end
end
