module ActionCandidatesHelper
  def action_candidate_type_label(action_candidate)
    case action_candidate.action_type
    when "new_article_candidate" then "📝 新規記事候補"
    when "article_create" then "📝 新規記事作成"
    when "article_update" then "📝 既存記事改訂"
    when "smoking_info_verify" then "🚬 喫煙情報確認"
    when "shop_phone_verify" then "☎ 電話確認"
    when "seo_improvement" then "🔧 既存ページ改善"
    when "seo_article" then "📝 SEO記事"
    else action_candidate.action_type.to_s
    end
  end
end
