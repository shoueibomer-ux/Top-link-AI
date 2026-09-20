"""Site-wide constants for the marketing website. Everything a deployment
might want to change without touching templates lives here or in env vars."""

import os

SITE_NAME = "Top-Link AI"
TAGLINE = "AI-Powered Service Matching"
CITY = "Edmonton"
REGION = "Alberta"

# Where the "Find a Service" / "Join as a Provider" / "Request Service"
# buttons send people. Empty means "use the on-site get-the-app page" —
# set these env vars to a store listing or web-app URL once one exists.
APP_URL = os.environ.get("WEBSITE_APP_URL", "")
PROVIDER_URL = os.environ.get("WEBSITE_PROVIDER_URL", "")
CONTACT_EMAIL = os.environ.get("WEBSITE_CONTACT_EMAIL", "")
