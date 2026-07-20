require "uri"

module Aicoo
  module Lovable
    class BuildUrl
      MAX_PROMPT_LENGTH = 50_000

      def self.call(prompt, base_url: Configuration.new.build_url)
        uri = URI(base_url)
        params = URI.decode_www_form(uri.query.to_s)
        params << [ "autosubmit", "true" ]
        uri.query = URI.encode_www_form(params)
        uri.fragment = "prompt=#{URI.encode_www_form_component(prompt.to_s.first(MAX_PROMPT_LENGTH))}"
        uri.to_s
      end
    end
  end
end
