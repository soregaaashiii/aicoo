module Aicoo
  class ExploreOpportunityGenerator
    Result = Data.define(:created, :skipped)
    MIN_SCORE = 70

    def self.generate_all_pending!
      new.generate_all_pending!
    end

    def initialize(observations: nil)
      @observations = observations
    end

    def generate_all_pending!
      created = []
      skipped = []

      scope.find_each do |observation|
        opportunity = generate_from_observation!(observation)
        opportunity ? created << opportunity : skipped << observation
      end

      Result.new(created:, skipped:)
    end

    def generate_from_observation!(observation, force: false)
      return observation.opportunity_discovery_item if observation.opportunity_discovery_item
      return if weak?(observation) && !force
      return duplicate_opportunity(observation) if duplicate_opportunity(observation)

      scores = scores_for(observation)
      opportunity = OpportunityDiscoveryItem.create!(
        business: matched_business(observation),
        source_observation: observation,
        title: observation.title,
        description: observation.description,
        summary: summary_for(observation),
        source_type: observation.explore_data_source.source_type,
        opportunity_type: opportunity_type_for(observation),
        opportunity_score: scores.fetch(:opportunity),
        market_signal_score: scores.fetch(:market_signal),
        urgency_score: scores.fetch(:urgency),
        monetization_score: scores.fetch(:monetization),
        feasibility_score: scores.fetch(:feasibility),
        competition_score: scores.fetch(:competition),
        expected_value_yen: expected_value_yen(scores),
        confidence: confidence_for(observation),
        status: "pending",
        discovered_at: observation.observed_at || Time.current,
        metadata: {
          "explore_observation_id" => observation.id,
          "auto_generated_from_explore" => true,
          "observation_type" => observation.observation_type
        }.merge(observation.metadata.to_h)
      )
      observation.update!(opportunity_discovery_item: opportunity, status: "converted")
      opportunity
    end

    private

    attr_reader :observations

    def scope
      (observations || ExploreObservation.includes(:explore_data_source).new_status).where("score >= ?", MIN_SCORE)
    end

    def weak?(observation)
      observation.score.to_d < MIN_SCORE
    end

    def duplicate_opportunity(observation)
      normalized = normalize(observation.title)
      OpportunityDiscoveryItem.where(source_type: observation.explore_data_source.source_type).detect do |opportunity|
        normalize(opportunity.title) == normalized ||
          opportunity.metadata.to_h["explore_observation_id"].to_i == observation.id
      end
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[[:space:]　]+/, "").gsub(/[^\p{Alnum}\p{Han}\p{Hiragana}\p{Katakana}]/, "")
    end

    def scores_for(observation)
      market_signal = clamp(observation.score)
      urgency = urgency_score(observation)
      monetization = monetization_score(observation)
      feasibility = feasibility_score(observation)
      competition = competition_score(observation)
      opportunity = clamp((market_signal * 0.35) + (urgency * 0.2) + (monetization * 0.25) + (feasibility * 0.2) - (competition * 0.15))

      {
        market_signal:,
        urgency:,
        monetization:,
        feasibility:,
        competition:,
        opportunity:
      }
    end

    def urgency_score(observation)
      base = observation.observed_at && observation.observed_at >= 7.days.ago ? 80 : 55
      base += 10 if observation.observation_type.in?(%w[anomaly trend])
      clamp(base)
    end

    def monetization_score(observation)
      source_type = observation.explore_data_source.source_type
      base = case source_type
      when "clarity", "google_business_profile"
        85
      when "google_trends", "youtube", "x"
        65
      else
        55
      end
      base += 10 if observation.observation_type.in?(%w[engagement opportunity])
      clamp(base)
    end

    def feasibility_score(observation)
      text = "#{observation.title} #{observation.description}".downcase
      return 85 if text.match?(/lp|ランディング|テスト|検証|記事|content|コンテンツ/)
      return 75 if observation.observation_type.in?(%w[trend discussion])

      60
    end

    def competition_score(observation)
      observation.observation_type == "competitor" ? 75 : 30
    end

    def confidence_for(observation)
      score = 35
      score += 25 if observation.score.to_d >= 80
      score += 15 if observation.description.present?
      score += 10 if observation.metadata.to_h.present?
      clamp(score)
    end

    def expected_value_yen(scores)
      value = (
        scores.fetch(:market_signal) * 800 +
        scores.fetch(:urgency) * 450 +
        scores.fetch(:monetization) * 900 +
        scores.fetch(:feasibility) * 500 -
        scores.fetch(:competition) * 350
      ).to_i
      [ value, 1_000 ].max
    end

    def matched_business(observation)
      text = "#{observation.title} #{observation.description}".downcase
      Business.order(:name).find { |business| text.include?(business.name.to_s.downcase) }
    end

    def opportunity_type_for(observation)
      return "lp_test" if observation.observation_type.in?(%w[trend opportunity])
      return "revenue_experiment" if observation.observation_type == "engagement"
      return "serp_research" if observation.explore_data_source.source_type == "google_trends"

      "content_test"
    end

    def summary_for(observation)
      observation.description.presence || "#{observation.explore_data_source.source_type}から検出したExploreシグナルです。"
    end

    def clamp(value)
      [ [ value.to_d, 0.to_d ].max, 100.to_d ].min
    end
  end
end
