"""Shared constants for provider_search. Used to hold the Google Places
integration (real-listing search); that feature was removed (see
ServiceRequestCreateView) along with everything it needed except the served
city list below, which accounts.serializers also validates business profiles
against.
"""

CITIES = ["Edmonton", "Calgary", "Fort McMurray", "Red Deer"]
# Where Tabmatch is open. Providers can pick only these; the other cities take a waitlist signup.
LAUNCHED_CITIES = ["Edmonton"]
WAITLIST_CITIES = [c for c in CITIES if c not in LAUNCHED_CITIES]
