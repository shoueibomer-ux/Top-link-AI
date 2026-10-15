# Tabmatch

A Flutter app (customers and providers) backed by a Django REST API. The
backend also serves the marketing website.

## Brand

The product is **Tabmatch** (navy `#0B1F3A`, turquoise `#19C3B1`). The wordmark is
lowercase: "tab" in white (navy on a light background) and "match" in turquoise.
`assets/brand/tabmatch_icon.svg` is the source icon; `tabmatch_icon_foreground.svg`
is the same shapes without the navy tile, for Android adaptive icons.

```bash
python tool/make_brand_assets.py      # PNGs in assets/brand + the website's favicon/social image (needs Pillow)
dart run flutter_launcher_icons       # Android, iOS and web launcher icons
dart run flutter_native_splash:create # Android/iOS/web splash screens
```

The package / bundle id (`com.toplinkai.app`), the Dart package name, the Render
service and database names and the `TOPLINKAI_*` environment variable still use
the old name on purpose.

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

### Building against this project's production backend

`API_BASE_URL` is `https://toplinkai-backend.onrender.com/api` — note the
trailing `/api`: every endpoint call appends its own path to this (see
`lib/api/api_client.dart`), matching how Django mounts everything under
`/api/` (see `config/urls.py`), so a value without it would 404 on every
request. `API_KEY` must be the exact value configured for the
`toplinkai-backend` web service's `API_KEY` env var on Render (see
`render.yaml`) — it is a real secret and is **never** committed here or
passed as a literal on the command line; export it in your own shell first:

```bash
export TOPLINKAI_PROD_API_KEY=<the value from Render's API_KEY env var>

# a release APK:
flutter build apk --release \
  --dart-define=API_BASE_URL=https://toplinkai-backend.onrender.com/api \
  --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"

# or run it directly on a connected device, same configuration:
flutter run --release \
  --dart-define=API_BASE_URL=https://toplinkai-backend.onrender.com/api \
  --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"
```

Windows PowerShell:

```powershell
$env:TOPLINKAI_PROD_API_KEY = "<the value from Render's API_KEY env var>"

# a release APK:
flutter build apk --release --dart-define=API_BASE_URL=https://toplinkai-backend.onrender.com/api --dart-define="API_KEY=$env:TOPLINKAI_PROD_API_KEY"

# or run it directly on a connected device, same configuration:
flutter run --release --dart-define=API_BASE_URL=https://toplinkai-backend.onrender.com/api --dart-define="API_KEY=$env:TOPLINKAI_PROD_API_KEY"
```

### Google sign-in for providers

Provider sign-in needs the Web OAuth client ID (Google Cloud project "tabmatch"):
the app passes it to Google as `serverClientId`, and the backend only accepts
ID tokens issued for it (Render env var `GOOGLE_OAUTH_CLIENT_IDS`, the same
value). It is an identifier, not a secret, but it lives in a git-ignored file
so each build machine sets its own:

```bash
cp dart_defines.example.json dart_defines.local.json   # then paste the Web client ID into it
flutter run --dart-define-from-file=dart_defines.local.json
flutter build apk --release --dart-define-from-file=dart_defines.local.json   --dart-define=API_BASE_URL=https://toplinkai-backend.onrender.com/api   --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"
```

Without it the sign-in screen says Google sign-in is not set up in this build.
Google also needs an **Android** OAuth client in the same project for package
`com.toplinkai.app` and the SHA-1 of the key that signed the build. Each
signing key has its own SHA-1: the debug key (per machine, from
`keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore`),
and later the release key or Google Play's app-signing key. Release builds are
currently signed with the debug key (see `android/app/build.gradle.kts`).

### Trying provider sign-in without a Google account (development only)

To click through the provider flow on the emulator without adding a Google
account, run the local dev server with `GOOGLE_DEV_FAKE_AUTH=True` (and
`DJANGO_DEBUG=True`), and a **debug** build with a fake email:

```bash
flutter run --dart-define=DEV_FAKE_GOOGLE_EMAIL=dev.provider@example.com
```

The app then sends `dev-fake:<email>` instead of a Google token. It can only
work when **all** of these hold, and each is enforced and tested:

- the app is a debug build (`kDebugMode`); profile and release builds ignore it,
  and a release build given the define refuses to start;
- the server has `GOOGLE_DEV_FAKE_AUTH=True` **and** `DEBUG=True`; with `DEBUG`
  off the token goes to real Google verification and fails, and the server's
  startup check (`providers.E001`, run by `migrate` in `build.sh`) refuses to
  start at all.

Never add `GOOGLE_DEV_FAKE_AUTH` to `render.yaml`, `.env.example` or the Render
dashboard (a test fails if it appears in `render.yaml`).

### Before publishing

Tick every box before a release goes to the Play Store, the App Store or real
providers:

- [ ] Real Google sign-in tested end to end on a **real device** (not only the
      emulator), with a real Google account, reaching the registration form.
- [ ] An **Android OAuth client** exists in Google Cloud (project "tabmatch") for
      `com.toplinkai.app` and the SHA-1 of the key that signs the release: your
      own release key, or Google Play's app-signing key if you use Play App
      Signing. The debug SHA-1 is not enough, and release builds are currently
      signed with the debug key (`android/app/build.gradle.kts`), so fix that
      first.
- [ ] `GOOGLE_OAUTH_CLIENT_IDS` is set on Render to the Web client ID, and the
      release build was made with that same `GOOGLE_SERVER_CLIENT_ID`.
- [ ] **Fake sign-in confirmed disabled:** `GOOGLE_DEV_FAKE_AUTH` is not set on
      Render (check the environment tab), the release command has no
      `DEV_FAKE_GOOGLE_EMAIL`, and a fake token is refused by the production
      server (`providers/tests.py`, `FakeSignInNeverInProductionTests`, passes).
- [ ] Providers can delete their account inside the app (an app-store
      requirement; not built yet).

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
