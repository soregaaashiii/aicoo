require "test_helper"

class BusinessPrototypesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:suelog)
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "creates and queues a prototype" do
    assert_difference("BusinessPrototype.count", 1) do
      assert_enqueued_with(job: Aicoo::BusinessRegistrationAnalysisJob) do
        post business_business_prototypes_url(@business), params: {
          business_prototype: {
            prototype_type: "lovable",
            name: "LP v1",
            location: "https://example.lovable.app"
          }
        }
      end
    end

    assert_redirected_to business_url(@business, anchor: "business-prototypes")
  end

  test "updates and requeues a prototype" do
    prototype = @business.business_prototypes.create!(
      prototype_type: "url",
      location: "https://old.example.com"
    )

    patch business_business_prototype_url(@business, prototype), params: {
      business_prototype: {
        prototype_type: "render",
        name: "Production",
        location: "https://new.example.com"
      }
    }

    assert_redirected_to business_url(@business, anchor: "business-prototypes")
    assert_equal "render", prototype.reload.prototype_type
    assert_equal "queued", prototype.analysis_status
  end

  test "deletes only the prototype" do
    prototype = @business.business_prototypes.create!(
      prototype_type: "figma",
      location: "https://figma.com/file/example"
    )

    assert_difference("BusinessPrototype.count", -1) do
      assert_no_difference("Business.count") do
        delete business_business_prototype_url(@business, prototype)
      end
    end
  end
end
