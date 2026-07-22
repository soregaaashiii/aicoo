require "test_helper"

module Aicoo
  module LpIntegration
    class ProductionVerifierTest < ActiveSupport::TestCase
      FakeFetcher = Struct.new(:response, :error) do
        def get(_url)
          raise error if error

          response
        end
      end

      setup do
        @business = Business.create!(name: "外部事業", status: "building", business_type: "saas")
        @business.create_business_execution_profile!(
          execution_type: "external_repo",
          repository_type: "rails",
          github_repository: "https://github.com/example/service",
          production_url: "https://service.example.com"
        )
        @prototype = @business.business_prototypes.create!(
          prototype_type: "url",
          name: "LP作成元",
          location: "https://source.example.com",
          metadata: { "role" => Overview::ROLE, "lp_source_type" => "public_url" }
        )
      end

      test "records a successful production verification" do
        response = Aicoo::PublicHttpFetcher::Response.new(
          body: "ok",
          content_type: "text/html",
          status: 200,
          url: "https://service.example.com/"
        )

        result = ProductionVerifier.new(
          business: @business,
          fetcher: FakeFetcher.new(response, nil)
        ).call

        assert result.success
        assert_equal "success", @prototype.reload.metadata["last_verification_status"]
        assert @prototype.metadata["last_verified_at"].present?
      end

      test "records a concise error without changing external data" do
        result = ProductionVerifier.new(
          business: @business,
          fetcher: FakeFetcher.new(nil, Aicoo::PublicHttpFetcher::Error.new("HTTP 500"))
        ).call

        assert_not result.success
        assert_equal "failed", @prototype.reload.metadata["last_verification_status"]
        assert_equal "HTTP 500", @prototype.metadata["last_error"]
      end
    end
  end
end
