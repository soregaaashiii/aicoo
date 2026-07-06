namespace :aicoo do
  desc "Trace and optionally archive ActionCandidates contaminated by an unrelated SERP URL"
  task trace_url_contamination: :environment do
    url = ENV["URL"].presence || "it-trend.jp/log_management/article/84-0008"
    fix = ActiveModel::Type::Boolean.new.cast(ENV["FIX"])

    result = Aicoo::UrlContaminationTracer.call(url:, fix:)
    puts JSON.pretty_generate(result.to_h)
  end

  desc "Archive SERP-contaminated Suelog candidates and regenerate internal-data candidates"
  task cleanup_suelog_serp_contamination: :environment do
    result = Aicoo::SuelogSerpContaminationCleanup.call(
      url: ENV["URL"].presence || Aicoo::SuelogSerpContaminationCleanup::DEFAULT_URL,
      regenerate: ENV.fetch("REGENERATE", "true")
    )
    puts JSON.pretty_generate(result.to_h)
  end
end
