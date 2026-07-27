require "digest"
require "openssl"
require "active_support/security_utils"

module Aicoo
  module Lovable
    class GithubWebhookSignature
      PREFIX = "sha256=".freeze

      def self.valid?(payload:, signature:, secret:)
        return false if payload.blank? || signature.blank? || secret.blank?

        expected = "#{PREFIX}#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(signature.to_s),
          Digest::SHA256.hexdigest(expected)
        )
      end
    end
  end
end
