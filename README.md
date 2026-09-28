# Top-Link AI

A Flutter app (customers and providers) backed by a Django REST API. The
backend also serves the marketing website.

## Running locally

```bash
# backend (needs Postgres + Redis; see .env.example)
python manage.py migrate
python manage.py runserver 0.0.0.0:8000

# app — debug builds need no configuration:
# localhost (or 10.0.2.2 on the Android emulator) and the dev API key
flutter run
```

## Release builds: required configuration

The app talks to the backend over HTTPS with a shared API key, both supplied
at build time. **A release build refuses to run without them** — it shows a
"This build is misconfigured" screen instead of the app — so a wrong build is
caught the moment it launches, not after users hit it.

| `--dart-define` | Release build requires | Debug build default |
|---|---|---|
| `API_BASE_URL` | set, and `https://` (e.g. `https://api.example.com/api`) | `http://localhost:8000/api` (`10.0.2.2` on the Android emulator) |
| `API_KEY` | set, and not the dev placeholder | `dev-local-shared-key` |

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  --dart-define=API_KEY=<the production key>
```

Why this is enforced in code rather than left to the OS: the app uses Dart's
`http` package, which ignores Android's `usesCleartextTraffic` and iOS's App
Transport Security, so nothing else would stop a cleartext production URL.

A debug build may use an `http://` `API_BASE_URL` (e.g. a LAN address so a real
phone can reach your dev server); a release build may not.

## Backend production settings

See `.env.example`. With `DJANGO_DEBUG=False` the backend requires
`DJANGO_SECRET_KEY`, `API_KEY`, a database (`DATABASE_URL`, or the five
`DB_*` settings) and `DJANGO_ALLOWED_HOSTS`, turns on HTTPS redirect / HSTS /
secure cookies, and needs `DJANGO_BEHIND_PROXY=True` only if a reverse proxy
terminates TLS for it.

## Deploying to Render

`render.yaml` is a [Blueprint](https://render.com/docs/blueprint-spec) that
provisions the backend as a web service plus a managed PostgreSQL database
and Redis-compatible cache: in the Render dashboard, New → Blueprint, point
it at this repo, and it reads `render.yaml` from there. `build.sh` (its
build command) installs dependencies, collects static files, and applies
migrations on every deploy. Render prompts for the handful of secrets
`render.yaml` doesn't set itself (the app's `API_KEY`, `GOOGLE_PLACES_API_KEY`,
etc. — see the comments at the top of that file); nothing else needs
manual configuration for a first deploy. Static files are served by
[whitenoise](https://whitenoise.readthedocs.io/), so no separate static host
or CDN is required to get started.
