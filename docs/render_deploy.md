# Render Free Web Service deploy

## Purpose

AICOO Lab LPs can be shared externally through published LP URLs while AICOO management screens stay protected.

Public paths:

- `/aicoo_lab/lp/:slug`
- `/aicoo_lab/lp/:slug/cta_click`
- `/aicoo_lab/lp/:slug/signup`

Management paths such as `/dashboard`, `/admin/*`, `/action_candidates`, `/judge`, and `/businesses` require Basic authentication in production.

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

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REFRESH_TOKEN`

## Verify after deploy

1. Open `/dashboard`.
2. Confirm Basic authentication is required.
3. Publish an AICOO Lab LP from the management screen.
4. Open `/aicoo_lab/lp/:slug` in an incognito browser.
5. Confirm the LP is visible without Basic authentication.
6. Submit CTA/signup and confirm PV/CTA/Signup are recorded.

`http://127.0.0.1:*` and `http://localhost:*` are local-only URLs and cannot be used for external SNS sharing.
