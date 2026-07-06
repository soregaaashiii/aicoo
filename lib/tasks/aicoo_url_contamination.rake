namespace :aicoo do
  desc "Trace and optionally archive ActionCandidates contaminated by an unrelated SERP URL"
  task trace_url_contamination: :environment do
    url = ENV["URL"].presence || "it-trend.jp/log_management/article/84-0008"
    fix = ActiveModel::Type::Boolean.new.cast(ENV["FIX"])

    result = Aicoo::UrlContaminationTracer.call(url:, fix:)
    puts JSON.pretty_generate(result.to_h)
  end
end
