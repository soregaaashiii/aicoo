module Aicoo
  class OpportunityDiscoveryService
    Result = Data.define(:created_count, :skipped_count)

    def call
      Result.new(created_count: 0, skipped_count: 0)
    end
  end
end
