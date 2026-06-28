# Render Free Web Service deploy

## Purpose

AICOO Lab LPs can be shared externally through published LP URLs while AICOO management screens stay protected.

Public paths:

- `/`
- `/lp`
- `/lp/:slug`
- `/lp/:slug/cta_click`
- `/lp/:slug/scroll`
- `/lp/:slug/signup`
- `/sitemap.xml`
- `/robots.txt`

Management paths such as `/dashboard`, `/owner`, `/admin/*`, `/action_candidates`, `/judge`, and `/businesses` require Basic authentication in production.

## Render settings

Create a Render Free Web Service from this repository.

Build command:

```sh
bundle install && SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

Start command:

```sh
bin/rails db:migrate && bin/rails server -b 0.0.0.0 -p $PORT
```

## Required environment variables

- `RAILS_ENV=production`
- `RAILS_SERVE_STATIC_FILES=true`
- `SECRET_KEY_BASE`
- `DATABASE_URL`
- `AICOO_PUBLIC_BASE_URL`
- `AICOO_BASIC_AUTH_USERNAME`
- `AICOO_BASIC_AUTH_PASSWORD`

Optional environment variables:

- `GA4_MEASUREMENT_ID` (example: `G-E5KCHJTFVP`)
- `GOOGLE_SITE_VERIFICATION`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REFRESH_TOKEN`

`AICOO_PUBLIC_BASE_URL` controls canonical URLs, sitemap URLs, and public LP URLs. Set it to the public host, such as `https://lab.aicoo.jp`, when moving away from the Render default domain.

## Verify after deploy

1. Open `/` and confirm the public LP top is visible without Basic authentication.
2. Open `/dashboard` and confirm Basic authentication is required.
3. Publish an AICOO Lab LP from the management screen.
4. Open `/lp/:slug` in an incognito browser.
5. Confirm the LP is visible without Basic authentication.
6. Confirm the page source contains canonical, Open Graph, Twitter Card, and GA4 tags.
7. Open `/sitemap.xml` and confirm only published LPs are listed with `lastmod`.
8. Submit CTA/signup and confirm PV/CTA/Signup/Scroll events are recorded.

Scheduled LPs use `public_status=scheduled` and `scheduled_publish_at`. They are published automatically the next time `/lp`, `/lp/:slug`, or `/sitemap.xml` is requested after the scheduled time.

`http://127.0.0.1:*` and `http://localhost:*` are local-only URLs and cannot be used for external SNS sharing.
