require "test_helper"

module Aicoo
  module Serp
    class AdapterTest < ActiveSupport::TestCase
      test "calls specified provider and returns normalized result" do
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.define_singleton_method(:body) do
          {
            organic: [
              {
                position: 1,
                title: "大阪の喫煙カフェ",
                link: "https://example.com/osaka-smoking-cafe",
                displayedLink: "example.com",
                snippet: "大阪で喫煙できるカフェの一覧"
              }
            ],
            peopleAlsoAsk: [ { question: "大阪で喫煙できるカフェは？" } ],
            relatedSearches: [ { query: "梅田 喫煙 カフェ" } ]
          }.to_json
        end

        with_env("SERPER_API_KEY" => "serper-key") do
          stub_http_start(lambda { |_host, _port, **_options, &block|
            http = Object.new
            http.define_singleton_method(:request) { |_request| response }
            block.call(http)
          }) do
            result = Adapter.call(
              provider: :serper,
              type: :google_search,
              query: "大阪 喫煙 カフェ",
              location: "Japan",
              language: "ja",
              limit: 10
            )

            payload = result.to_h
            assert_equal "serper", payload["provider"]
            assert_equal "google_search", payload["type"]
            assert_equal "大阪 喫煙 カフェ", payload["query"]
            assert_equal 1, payload["organic_results"].size
            assert_equal "大阪の喫煙カフェ", payload.dig("organic_results", 0, "title")
            assert_equal "大阪で喫煙できるカフェは？", payload.dig("people_also_ask", 0, "question")
            assert_equal [ "梅田 喫煙 カフェ" ], payload["related_searches"]
          end
        end
      end

      test "raises for unsupported search type" do
        with_env("SERPER_API_KEY" => "serper-key") do
          error = assert_raises(UnsupportedSearchTypeError) do
            Adapter.call(provider: :serper, type: :google_maps, query: "大阪 喫煙 カフェ")
          end

          assert_includes error.message, "未対応"
        end
      end

      test "raises when api key is missing" do
        DataSourceCostProfile.find_by(source_key: "serp")&.update!(api_key: nil)

        with_env("SERPER_API_KEY" => nil) do
          error = assert_raises(MissingApiKeyError) do
            Adapter.call(provider: :serper, type: :google_search, query: "大阪 喫煙 カフェ")
          end

          assert_includes error.message, "SERPER_API_KEY"
        end
      end

      test "data for seo provider is explicit placeholder" do
        error = assert_raises(UnsupportedSearchTypeError) do
          Adapter.call(provider: :data_for_seo, type: :google_search, query: "大阪 喫煙 カフェ")
        end

        assert_includes error.message, "未実装"
      end

      private

      def with_env(values)
        previous = values.transform_values { |_value| nil }
        values.each do |key, value|
          previous[key] = ENV[key]
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
        yield
      ensure
        previous.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
      end

      def stub_http_start(handler)
        singleton = class << Net::HTTP; self; end
        original_start = Net::HTTP.method(:start)
        singleton.define_method(:start) { |*args, **kwargs, &block| handler.call(*args, **kwargs, &block) }
        yield
      ensure
        singleton.define_method(:start) { |*args, **kwargs, &block| original_start.call(*args, **kwargs, &block) }
      end
    end
  end
end
