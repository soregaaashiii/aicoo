module ActionCandidatesHelper
  def action_candidate_type_label(action_candidate)
    case action_candidate.action_type
    when "new_article_candidate" then "📝 新規記事候補"
    when "seo_improvement" then "🔧 既存ページ改善"
    when "seo_article" then "📝 SEO記事"
    else action_candidate.action_type.to_s
    end
  end
end
