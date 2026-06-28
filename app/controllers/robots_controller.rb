class RobotsController < ApplicationController
  def show
    render plain: <<~ROBOTS
      User-agent: *
      Allow: /
      Allow: /robots.txt
      Allow: /sitemap.xml
      Allow: /lp
      Allow: /lp/
      Disallow: /owner
      Disallow: /admin
      Disallow: /settings
      Disallow: /system
      Disallow: /dashboard
      Disallow: /action_candidates
      Disallow: /action_results
      Disallow: /businesses
      Disallow: /aicoo_setting
      Disallow: /aicoo_daily_runs
      Disallow: /api

      Sitemap: #{helpers.public_absolute_url(sitemap_path(format: :xml))}
    ROBOTS
  end
end
