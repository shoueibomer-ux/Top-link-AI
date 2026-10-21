"""Error monitoring (Sentry), on only when SENTRY_DSN is set.

Errors only (no performance tracing), and nothing personal leaves the server:
no request bodies (chat messages, profile edits), cookies, headers, query
strings, user identity or local variables, and any email address, phone
number or token that ends up inside an error message is replaced before
sending. What is left is the exception type, its stack trace (file/line/
function names) and the request's method and path.
"""

import re

REDACTED = "[redacted]"

_PATTERNS = [
    # JWTs (access/refresh tokens): three base64url parts, the first "eyJ".
    re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
    re.compile(r"(?i)\bbearer\s+\S+"),
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    # Long letter-and-digit runs: API keys, Google ID tokens, FCM tokens.
    re.compile(r"(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{24,}"),
    # Phone numbers in any common format (+1 780 555 0100, (780) 555-0100, 7805550100).
    re.compile(r"\+?\d[\d\s().-]{6,}\d"),
]

# Request fields kept; everything else under event["request"] is dropped.
_REQUEST_KEEP = ("method", "url")


def scrub_text(value):
    if not isinstance(value, str):
        return value
    for pattern in _PATTERNS:
        value = pattern.sub(REDACTED, value)
    return value


def _scrub_request(request):
    kept = {k: request[k] for k in _REQUEST_KEEP if k in request}
    if "url" in kept:
        # Paths only; the query string can carry search text or ids.
        kept["url"] = scrub_text(kept["url"].split("?", 1)[0])
    return kept


def _scrub_breadcrumb(crumb):
    # Breadcrumb data holds SQL parameters, log arguments and URLs with
    # query strings; keep only what kind of step it was and a scrubbed line.
    return {
        k: (scrub_text(v) if k == "message" else v)
        for k, v in crumb.items()
        if k in ("type", "category", "level", "timestamp", "message")
    }


def before_send(event, hint):
    if "request" in event:
        event["request"] = _scrub_request(event["request"])
    for key in ("user", "extra"):
        event.pop(key, None)

    for exc in event.get("exception", {}).get("values", []):
        exc["value"] = scrub_text(exc.get("value"))
        for frame in (exc.get("stacktrace") or {}).get("frames", []):
            frame.pop("vars", None)

    if isinstance(event.get("message"), str):
        event["message"] = scrub_text(event["message"])
    logentry = event.get("logentry")
    if logentry:
        logentry["message"] = scrub_text(logentry.get("message"))
        # Formatted log arguments can be anything (a phone, a message body).
        logentry.pop("params", None)
        if "formatted" in logentry:
            logentry["formatted"] = scrub_text(logentry["formatted"])

    breadcrumbs = event.get("breadcrumbs")
    if isinstance(breadcrumbs, dict) and "values" in breadcrumbs:
        breadcrumbs["values"] = [_scrub_breadcrumb(c) for c in breadcrumbs["values"]]
    return event


def before_breadcrumb(crumb, hint):
    return _scrub_breadcrumb(crumb)


def init_sentry(dsn, environment, release=None):
    import sentry_sdk
    from sentry_sdk.integrations.django import DjangoIntegration

    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=release or None,
        integrations=[DjangoIntegration()],
        send_default_pii=False,
        include_local_variables=False,
        max_request_body_size="never",
        traces_sample_rate=0,
        before_send=before_send,
        before_breadcrumb=before_breadcrumb,
    )
