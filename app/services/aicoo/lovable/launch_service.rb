module Aicoo
  module Lovable
    class LaunchService
      def initialize(launcher: BuildWithUrlLauncher.new)
        @launcher = launcher
      end

      def call(prompt:, image_urls: [])
        launcher.call(prompt:, image_urls:)
      end

      private

      attr_reader :launcher
    end
  end
end
