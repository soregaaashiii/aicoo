module Aicoo
  module IdeaPipeline
    class PipelineRunner
      def initialize(item)
        @item = item
      end

      def run_next!
        case item.current_stage
        when "idea"
          IdeaScorer.new(item).call
        when "score"
          SerpEvaluator.new(item).call
        when "serp"
          LandingPageBuilder.new(item).call
        when "lp"
          Publisher.new(item).call
        when "publish"
          LearningEvaluator.new(item).call
        when "learning"
          MvpSpecBuilder.new(item).call
        else
          item
        end
      end

      def run_until_blocked!
        6.times do
          previous_state = [ item.current_stage, item.status, item.updated_at ]
          run_next!
          item.reload
          Aicoo::PipelineEngine.new(item).call
          break if blocked?
          break if previous_state == [ item.current_stage, item.status, item.updated_at ]
        end
        item
      end

      private

      attr_reader :item

      def blocked?
        item.status.in?(%w[serp_blocked ended continuing improving mvp_spec_ready])
      end
    end
  end
end
