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

The app talks to the backend over HTTPS with a shared API key, supplied at
build time. **A release build refuses to run without the key, or with an
`http://` URL** — it shows a "This build is misconfigured" screen instead of
the app — so a wrong build is caught the moment it launches, not after users
hit it. Without `API_BASE_URL` a release build talks to production,
`https://tabmatch.ca/api`.

| `--dart-define` | Release build requires | Debug build default |
|---|---|---|
| `API_BASE_URL` | `https://` if set; defaults to `https://tabmatch.ca/api` | `http://localhost:8000/api` (`10.0.2.2` on the Android emulator) |
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

`API_BASE_URL` is `https://tabmatch.ca/api` (the default, so it can be left
out; builds made before the custom domain use
`https://toplinkai-backend.onrender.com/api`, which keeps working) — note the
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
  --dart-define=API_BASE_URL=https://tabmatch.ca/api \
  --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"

# or run it directly on a connected device, same configuration:
flutter run --release \
  --dart-define=API_BASE_URL=https://tabmatch.ca/api \
  --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"
```

Windows PowerShell:

```powershell
$env:TOPLINKAI_PROD_API_KEY = "<the value from Render's API_KEY env var>"

# a release APK:
flutter build apk --release --dart-define=API_BASE_URL=https://tabmatch.ca/api --dart-define="API_KEY=$env:TOPLINKAI_PROD_API_KEY"

# or run it directly on a connected device, same configuration:
flutter run --release --dart-define=API_BASE_URL=https://tabmatch.ca/api --dart-define="API_KEY=$env:TOPLINKAI_PROD_API_KEY"
```

### Sign-in with an emailed code

Clients and providers can also tap *Continue with email*: they get a 6-digit code by email and type it in. No
passwords. A new email makes a new account; an email that already has one (also one made with Google) signs into
it. A code works once, for 10 minutes, with 5 wrong tries; sends are limited to 5 an hour per address and 20 per IP.
Code is in `accounts/email_login.py`.

- **Production (Render web service):** set `EMAIL_HOST_USER` (the Gmail address) and `EMAIL_HOST_PASSWORD` (a Gmail
  app password, not the account password). Optional: `DEFAULT_FROM_EMAIL` (defaults to `EMAIL_HOST_USER`), and
  `EMAIL_HOST` / `EMAIL_PORT` / `EMAIL_USE_TLS` for a provider other than Gmail (defaults `smtp.gmail.com`, `587`,
  `True`). Without both of the first two the option is hidden in the app and Google sign-in works as before.
- **Local development (`DJANGO_DEBUG=True`):** no email is sent; the code is printed in the `runserver` console.

### Google sign-in for providers

Provider sign-in needs the Web OAuth client ID (Google Cloud project "tabmatch"):
the app passes it to Google as `serverClientId`, and the backend only accepts
ID tokens issued for it (Render env var `GOOGLE_OAUTH_CLIENT_IDS`, the same
value). It is an identifier, not a secret, but it lives in a git-ignored file
so each build machine sets its own:

```bash
cp dart_defines.example.json dart_defines.local.json   # then paste the Web client ID into it
flutter run --dart-define-from-file=dart_defines.local.json
flutter build apk --release --dart-define-from-file=dart_defines.local.json   --dart-define=API_BASE_URL=https://tabmatch.ca/api   --dart-define=API_KEY="$TOPLINKAI_PROD_API_KEY"
```

Clients sign in with Google too, using the same Web client ID. The app asks at
the end of the request questions (not before), because a request now belongs to
the account that sent it: "Your requests", marking a job complete, and later
chat and reviews all go through that account. One Google account is one role: an
email that belongs to a provider can't sign in as a client, and the other way
round. Requests are listed at `GET /api/requests/mine/` for the signed-in client
only (the old device-id listing is gone, so a phone number is never readable
without signing in). Without the client ID the sign-in screen says Google
sign-in is not set up in this build.
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

### Chat and push notifications

Once a provider accepts a request, the client and that provider can chat in the app (text and photos),
and the client can call them. Only the two people on that offer can ever see the conversation: every
endpoint answers a stranger with the same 404 as a conversation that does not exist.

- **How messages arrive:** the open chat screen asks the server every few seconds for anything newer than
  the last message it has (a cursor, `since_id`), and only while the screen is open and the app is in
  front. A push notification wakes the app when it isn't. This is polling, not WebSockets: it works on the
  current single web instance without moving the whole backend to ASGI, at the cost of a delay of a few
  seconds. The API is the same one WebSockets would use, so the app would not change if that is added later.
- **Push:** Firebase Cloud Messaging. The text is generic ("<name> sent you a message"); the message never
  leaves the app. Needs two things, neither in the repo:
  - the Firebase service-account JSON as the Render env var `FCM_SERVICE_ACCOUNT_JSON` (web service), and
  - `google-services.json` from the Firebase console saved as `android/app/google-services.json` on every
    machine that builds the Android app (git-ignored; without it the app still builds, push is just off).
- **Photos:** a private Cloudflare R2 bucket. The app uploads straight to R2 with a 10-minute signed link and
  reads a photo through a 15-minute signed link that only the two people in the chat are given. The bucket is
  never public. Needs the Render env vars `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and
  `R2_BUCKET`. Without them text chat works and the photo button is hidden.
- **Check your keys** (shows only OK / OFF, never a value): in the Render Shell run
  `python manage.py check_messaging_config`, and add `--live` to make one harmless real call to Firebase and R2.
- **Safety (required by the app stores):** anyone can report a message (long-press) or block the other person;
  a first message needs agreement to the chat rules. Staff moderate in the Django admin under *Messaging*:
  *Message reports* is the queue (hide the message, or suspend the sender and hide it, or dismiss), and a
  hidden message shows to both people as "removed by a moderator". Photos in reports open through a private link.
- **Calling:** the Call button opens the phone's dialer with the other person's number, and only after the
  provider has accepted. `CALL_MASKING_ENABLED` is reserved for phase 2 (Twilio masked calls, not built yet);
  while it is on the server refuses calls (501) rather than silently ignoring it. The app does not change.

### Answering leads, locations and city waitlists

- **Accept / Decline in the app:** a lead card waiting for an answer has Accept and Decline buttons
  (`POST /api/provider/leads/<id>/accept|decline/`). It is the same answer as replying `YES <number>` /
  `NO <number>` to the text: both go through `LeadOffer.record_reply`, so whichever comes first wins and a second
  answer by any route changes nothing (the app says it was already answered). Accepting also texts the client's
  phone to the provider, exactly like the SMS YES. The text reply keeps working. `reply_channel` records `app`.
- **Where the job is:** the request form asks for the phone's location *or* a postal code / address
  (`ServiceRequest.location`). Coordinates are never shown or sent. A provider sees the location only after
  accepting, like the description. "Use my current location" turns the position into a postal code with the
  phone's own geocoder (no key needed); if that is unavailable the person types it.
- **Cities:** only Edmonton can be served (`provider_search.services.LAUNCHED_CITIES`). Providers can join a
  waitlist for the other cities (`ProviderProfile.waitlist_cities`); to open a city, add it to `LAUNCHED_CITIES`.
- **Notifications are asked for once**, after a client sends their first request or a provider accepts their
  first lead, not when the app opens. Settings has an on/off switch that shows the real state.

### Reviews and favorites

After a client marks a job complete they can rate the provider (1-5 stars, optional comment). Nothing
here needs a key or any Render setting; the migration only adds tables.

- **Rules:** one review per completed job, written only by the client who owns the request, editable for
  7 days. A provider can post one public reply per review (it can't be edited by them; staff can clear it).
- **What is public:** the provider's average rating and review count (on their profile, their page, the
  matches list, Favorites and the client's History), and the reviews with the client shown as "Pat P.".
  No phone number or email is ever in a review.
- **Favorites:** the heart on a provider's page saves them; the menu's *Favorites* lists them. Only clients
  can save, and only approved providers.
- **Safety:** anyone signed in can report a review (flag icon); reports stay up until staff look. In the
  Django admin under *Reviews*: *Review reports* is the queue (hide the review, or dismiss), and *Reviews* has
  hide / restore / remove-reply actions. A hidden review disappears from every page and no longer counts
  toward the rating; its author is told it was removed.

### Growth: neighbourhood pages, seasonal reminders, invites

All in the `growth` app plus `website/local_pages.py`; no paid service. The admin's **Growth dashboard**
(under *Growth*) shows requests per week by source (SEO page, seasonal reminder, invite, direct) and how many
were accepted and completed. Each request's `source` / `source_ref` is set by `growth.attribution`.

- **Neighbourhood pages:** `/edmonton/<neighbourhood>/<service>/` for every launched service with copy in
  `website/content/local_services.py` and every neighbourhood in `website/content/neighbourhoods.py` (30 to start),
  plus `/edmonton/` and a hub per neighbourhood. They are built from data (housing era, traits, garage and basement
  type, access notes), listed in `sitemap.xml`, and a test fails if two pages for a service get too alike. Add a
  neighbourhood or a service's copy there and the pages appear; un-launching a service takes its pages down.
- **"Request this service"** goes to `/open/request/?service=...&src=seo&ref=...`, which offers
  `tabmatch://open/request?...` (the app opens the request flow with the service chosen) or the get-the-app page.
  Someone who installs the app first and opens it later is counted as direct.
- **Seasonal reminders** (`growth/campaigns.py`, sent by the 15-minute cron job): one push and one email per
  in-season campaign to past clients of that service (a completed job in the last 2 years, or a request in the
  last 6 months), at most one a month, 10:00-19:00 Edmonton time, logged as *Reminder sends*. Off until the cron
  service has `SEASONAL_REMINDERS_ENABLED=True`; emails also need `SITE_URL` and `BUSINESS_MAILING_ADDRESS` (CASL
  requires a mailing address), and push needs `FCM_SERVICE_ACCOUNT_JSON` on the cron service. Clients turn them off
  in Settings or with the unsubscribe link (one-click unsubscribe headers included).
- **Invites:** every client has a link (`/invite/<code>/`, Settings > *Invite friends*). After a completed,
  reviewed job, History offers *Share this provider* (WhatsApp, text, copy link: the invite link naming the
  provider) and *Book again*. A new account (30 days or less) that opened an invite link, or typed the code in
  Settings, is recorded as an *Invite sign-up*, and its first request counts for that invite.

### Account deletion and the legal pages

- **In the app:** *Delete my account* is in Settings / the Profile tab for clients, and in the provider's Profile
  tab (also on the pending-review and registration screens) for providers. The person must type `DELETE`. It calls
  `POST /api/accounts/delete/`, then the app signs out and returns to the first screen.
- **What it does** (all in `accounts/deletion.py`, one transaction): deletes chats and their messages, push tokens,
  favorites, blocks, the chat-rules agreement and the Google link; blanks the name and email on the account (it
  stays as an inactive, anonymous row because a provider profile hangs off it); blanks a client's request details
  (phone, description, location, device id); turns a provider profile into an anonymous "Deleted provider"; closes
  open offers so nobody is asked to answer them; keeps reviews a client wrote (shown as "A client"), anonymous
  request / offer rows, and an `AccountDeletion` record (no personal data). Staff accounts are refused.
- **Chat photos in R2** are queued (`messaging.PhotoDeletion`) before anything is removed, deleted right after, and
  retried by the 15-minute jobs command (give the cron service the four `R2_*` values) or by
  `python manage.py purge_photo_queue`. `check_messaging_config` shows how many are waiting.
- **Someone who can't use the app** emails the contact address (see `/delete-account/`). Staff delete them from the
  admin (*Accounts > User profiles > Delete the selected accounts*, with a confirmation page) or with
  `python manage.py delete_account --email someone@example.com --yes` (without `--yes` it only says what it would do).
- **Website pages:** `/privacy/`, `/terms/`, `/provider-agreement/` (drafts, `noindex`, marked for a lawyer, with
  orange placeholders for decisions still to make) and `/delete-account/` (public; this is the URL Google Play asks
  for). They are linked from the footer and the app opens them from Settings. They print the contact email from
  `WEBSITE_CONTACT_EMAIL` on Render, `connect@tabmatch.ca` when it is unset.

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
- [ ] Chat tested on **two real devices**: a push arrives with the app closed, tapping it opens the chat,
      a photo sends and shows, and report / block work. (`check_messaging_config --live` is OK on Render.)
- [ ] The Firebase project has the **release / Play app-signing SHA-1** added, and the release build was made
      with the matching `google-services.json`.
- [ ] The R2 bucket is private (no public development URL, no custom domain).
- [ ] **Account deletion** tested on a real device for a client and for a provider (Settings / Profile >
      Delete my account), and a chat photo really disappears from the R2 bucket afterwards.
- [ ] `connect@tabmatch.ca` (or `WEBSITE_CONTACT_EMAIL` on Render, which overrides it) is a mailbox someone
      reads (the privacy and delete-account pages show it), and a test deletion request sent to it is handled.
- [ ] A lawyer has reviewed `/privacy/`, `/terms/` and `/provider-agreement/`, every orange placeholder is
      filled or decided, and the "DRAFT" banner is removed. In Play Console the account-deletion URL is
      `https://<your-host>/delete-account/`, and the Data safety form matches the privacy policy.
- [ ] Rate limits see real client IPs behind Render's proxy: signed in to the admin, open
      `https://<your-host>/<ADMIN_URL_PATH>/client-ip/` and check "Rate limits key on" is your own public IP
      (compare with any "what is my IP" site), also with `curl -H "X-Forwarded-For: 1.2.3.4"` (it must not
      show 1.2.3.4). If it shows a Render/Cloudflare address instead, set `TRUSTED_PROXY_HOPS` accordingly.
- [ ] `ADMIN_URL_PATH` is set on Render (the admin is then only there, not at `/admin/`).
- [ ] Sentry: `SENTRY_DSN` set on Render and in the release build's dart-defines, and a test error from each
      shows up in sentry.io with no personal data in it.
- [ ] Render Postgres backups confirmed for the database's plan (see "Backend production settings").

## Backend production settings

See `.env.example`. With `DJANGO_DEBUG=False` the backend requires
`DJANGO_SECRET_KEY`, `API_KEY`, a database (`DATABASE_URL`, or the five
`DB_*` settings) and `DJANGO_ALLOWED_HOSTS`, turns on HTTPS redirect / HSTS /
secure cookies, and needs `DJANGO_BEHIND_PROXY=True` only if a reverse proxy
terminates TLS for it.

Checked for launch: the live site runs with `DEBUG` off (it serves the branded 404, not Django's debug page),
sends HSTS (preload), `nosniff` and `X-Frame-Options: DENY`, redirects HTTP to HTTPS, and `manage.py check --deploy`
reports nothing. The app refuses to start without a real `DJANGO_SECRET_KEY` when `DEBUG` is off.

Known gaps to close before a public launch:

- **Rate limits and the proxy (done, verify after deploy).** Limits read the client IP from `X-Forwarded-For`
  through `config.client_ip`: only the entry Render's proxy appended (the `TRUSTED_PROXY_HOPS`-th from the right,
  1 on Render) is trusted, so a client-sent header can't pick its own bucket. Signed-in callers are limited per
  account (`user_or_ip`), anonymous ones per IP. Check it with the admin's `client-ip/` page (checklist above).
- **The Django admin (done).** It is served at `ADMIN_URL_PATH`, required with `DEBUG` off (`/admin/` only in dev),
  and its login is limited to 5 tries a minute per IP and 10 an hour per username (`config/admin_login.py`). Still
  use a long unique password, and remove `DJANGO_SUPERUSER_PASSWORD` from Render once the admin exists.
- **Error monitoring (done, needs `SENTRY_DSN`).** Sentry for the backend (`config/sentry.py`) and the app
  (`lib/monitoring/error_reporting.dart`), each on only with a DSN. Errors only; request bodies, headers, cookies,
  query strings, users, local variables and breadcrumb data are dropped, and emails, phone numbers and tokens in
  error messages are replaced.
- **The shared `API_KEY` is inside every app install.** It only keeps casual scrapers off; real protection is the
  per-user login, so keep new endpoints behind login and rate limits.
- Confirm the **Postgres backups and plan size** on Render match what you need to restore from.

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
