module Aicoo
  class SerpLandingPageCandidateGenerator
    Result = Data.define(:serp_analysis, :candidates)

    def initialize(keyword:, raw_text:, business: nil, location: nil, device: "desktop")
      @keyword = keyword.to_s.strip
      @raw_text = raw_text.to_s
      @business = business
      @location = location.to_s.strip
      @device = device.presence || "desktop"
    end

    def call
      validate!

      serp_analysis = import_serp_analysis
      candidates = build_candidates(serp_analysis)

      Result.new(serp_analysis:, candidates:)
    end

    private

    attr_reader :keyword, :raw_text, :business, :location, :device

    def validate!
      raise ArgumentError, "キーワードを入力してください。" if keyword.blank?
      raise ArgumentError, "SERP検索結果を入力してください。" if raw_text.blank?
    end

    def import_serp_analysis
      SerpAnalysisImportService.new(
        target_business,
        keyword:,
        raw_text:,
        filename: "serp_lp_candidates_#{Time.current.to_i}.txt",
        location:,
        device:
      ).call.serp_analysis
    end

    def target_business
      business || Business.order(:created_at).first || Business.create!(name: "AICOO SERP Research")
    end

    def build_candidates(serp_analysis)
      candidate_payloads(serp_analysis).map do |payload|
        SerpLandingPageCandidate.create!(payload.merge(serp_analysis:))
      end
    end

    def candidate_payloads(serp_analysis)
      [
        low_cost_lp_payload(serp_analysis),
        comparison_lp_payload(serp_analysis),
        checklist_lp_payload(serp_analysis)
      ].uniq { |payload| payload[:lp_title] }
    end

    def low_cost_lp_payload(serp_analysis)
      {
        keyword:,
        service_name: service_name("支援サービス"),
        target_audience: target_audience,
        problem: "#{keyword}を探している人は、比較・選定・実行方法がまとまっておらず判断に時間がかかっています。",
        lp_title: "#{keyword}の選び方を短時間で整理する",
        lp_description: "#{keyword}について、候補比較・注意点・次の一手を1ページで確認できるLPです。",
        cta_text: "無料で相談する",
        expected_value_score: expected_value_score(serp_analysis, modifier: 1.0),
        competition_note: competition_note(serp_analysis),
        metadata: metadata_for(serp_analysis, "low_cost_lp")
      }
    end

    def comparison_lp_payload(serp_analysis)
      {
        keyword:,
        service_name: service_name("比較ガイド"),
        target_audience: "#{keyword}で複数候補を比較しているユーザー",
        problem: "検索結果には競合や情報サイトが混在しており、どれを選べばよいか判断しにくい状態です。",
        lp_title: "#{keyword}の比較ガイド",
        lp_description: "#{keyword}の主要な選択肢、料金感、向いている人を整理して、問い合わせ前の迷いを減らします。",
        cta_text: "比較表を見る",
        expected_value_score: expected_value_score(serp_analysis, modifier: 0.9),
        competition_note: competition_note(serp_analysis),
        metadata: metadata_for(serp_analysis, "comparison_lp")
      }
    end

    def checklist_lp_payload(serp_analysis)
      {
        keyword:,
        service_name: service_name("チェックリスト"),
        target_audience: "#{keyword}で失敗したくない検討者",
        problem: "検討時に確認すべき条件が分散しており、問い合わせや購入前の不安が残りやすい状態です。",
        lp_title: "#{keyword}の失敗しないチェックリスト",
        lp_description: "#{keyword}を選ぶ前に確認すべき条件を整理し、具体的な次アクションへつなげます。",
        cta_text: "チェックリストを受け取る",
        expected_value_score: expected_value_score(serp_analysis, modifier: 0.8),
        competition_note: competition_note(serp_analysis),
        metadata: metadata_for(serp_analysis, "checklist_lp")
      }
    end

    def expected_value_score(serp_analysis, modifier:)
      result_count_score = [ serp_analysis.result_count.to_i * 5, 40 ].min
      competition_penalty = serp_analysis.competition_score.to_i * 0.35
      base = 70 + result_count_score - competition_penalty
      [ [ (base * modifier).round(2), 10 ].max, 100 ].min
    end

    def service_name(suffix)
      "#{keyword} #{suffix}"
    end

    def target_audience
      "#{keyword}を検索していて、短時間で良い選択肢を知りたいユーザー"
    end

    def competition_note(serp_analysis)
      top_results = serp_analysis.serp_results.order(:position).limit(5).map do |result|
        "#{result.position}. #{result.title.presence || result.url}"
      end
      [
        "競合強度: #{serp_analysis.competition_score}/100",
        "検索結果数: #{serp_analysis.result_count}",
        *top_results
      ].join("\n")
    end

    def metadata_for(serp_analysis, candidate_type)
      {
        candidate_type:,
        source: "serp",
        location:,
        device:,
        serp_analysis_id: serp_analysis.id,
        generated_at: Time.current.iso8601
      }
    end
  end
end
