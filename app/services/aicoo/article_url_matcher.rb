module Aicoo
  class ArticleUrlMatcher
    Result = Data.define(:article_id, :confidence, :matched_path, :match_type, :reason)

    def initialize(articles:)
      @articles = Array(articles)
      @indexes = build_indexes
    end

    def match(page)
      raw = page.to_s.strip
      return none("blank_page") if raw.blank?

      normalized = Aicoo::UrlNormalizer.call(raw)

      exact_article = indexes[:raw][raw]
      return result(exact_article, 1.0, normalized, "exact") if exact_article

      if normalized.present?
        canonical_article = indexes[:canonical][normalized]
        return result(canonical_article, 0.98, normalized, "canonical") if canonical_article

        path_article = indexes[:path][normalized]
        return result(path_article, 0.95, normalized, "normalized") if path_article

        slug_article = indexes[:slug][slug_from_path(normalized)]
        return result(slug_article, 0.85, normalized, "slug") if slug_article
      end

      partial_article = partial_match(raw, normalized)
      return result(partial_article, 0.6, normalized, "partial") if partial_article

      none("no_article_match", normalized)
    end

    private

    attr_reader :articles, :indexes

    def build_indexes
      articles.each_with_object({ raw: {}, canonical: {}, path: {}, slug: {}, searchable: [] }) do |article, memo|
        canonical = article_canonical_url(article)
        path = article_path(article)
        slug = safe_attr(article, "slug").to_s.strip

        [ canonical, path ].compact_blank.each { |raw_url| memo[:raw][raw_url.to_s.strip] ||= article }
        memo[:canonical][Aicoo::UrlNormalizer.call(canonical)] ||= article if canonical.present?
        memo[:path][Aicoo::UrlNormalizer.call(path)] ||= article if path.present?
        memo[:slug][slug] ||= article if slug.present?
        memo[:searchable] << [
          article,
          {
            canonical: canonical.to_s.downcase,
            path: path.to_s.downcase,
            slug: slug.to_s.downcase,
            title: safe_attr(article, "title").to_s.downcase
          }
        ]
      end
    end

    def partial_match(raw, normalized)
      needle = [ raw, normalized, slug_from_path(normalized) ].compact_blank.join(" ").downcase
      return if needle.blank?

      indexes[:searchable].find do |_article, fields|
        slug = fields[:slug]
        title = fields[:title]
        [ fields[:canonical], fields[:path], slug ].compact_blank.any? { |value| needle.include?(value) || value.include?(needle) } ||
          (title.present? && (needle.include?(title) || title.include?(needle))) ||
          (slug.present? && needle.include?(slug))
      end&.first
    end

    def result(article, confidence, matched_path, match_type)
      Result.new(article_id: article&.id, confidence:, matched_path:, match_type:, reason: nil)
    end

    def none(reason, matched_path = nil)
      Result.new(article_id: nil, confidence: 0.0, matched_path:, match_type: "none", reason:)
    end

    def slug_from_path(path)
      path.to_s.split("/").last.presence
    end

    def article_path(article)
      return article.public_path if article.respond_to?(:public_path) && safe_attr(article, "slug").present?

      first_existing_attr(article, %w[url canonical_url public_url source_url path page_path])
    end

    def article_canonical_url(article)
      first_existing_attr(article, %w[canonical_url canonical public_url url])
    end

    def safe_attr(record, attr)
      return unless record.respond_to?(attr)

      record.public_send(attr)
    end

    def first_existing_attr(record, attrs)
      attrs.lazy.map { |attr| safe_attr(record, attr) }.find(&:present?)
    end
  end
end
