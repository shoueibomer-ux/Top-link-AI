"""Static marketing copy shared across website pages.

The last item of every tuple is a Lucide icon name (see website/icons.py).
"""

# (name, text, icon)
JOURNEY_STEPS = [
    ("Search", "You look for a local service on Google.", "search"),
    ("Top-Link AI", "You land on the Top-Link AI website.", "monitor"),
    ("Choose", "Pick the service category you need.", "layout-grid"),
    ("Select", "Compare providers and pick the right one.", "users"),
    ("Request", "Send your service request.", "send"),
    ("Connect", "Continue the conversation in the Top-Link AI app.", "message-circle"),
]

# (title, text, icon)
HOW_IT_WORKS = [
    ("Choose a service", "Browse the sectors and pick what you need, or describe the job in your own words.", "layout-grid"),
    ("Tell us the details", "Say how urgent it is and where you are located.", "clipboard-list"),
    ("Compare providers", "See local providers with their public ratings, review counts and availability.", "columns-2"),
    ("Connect in the app", "Reach out to the provider you like and keep everything in one place.", "message-circle"),
]

# (title, description, coming_soon, icon)
PROVIDER_FEATURES = [
    ("Register as a provider",
     "Create a business account in the Top-Link AI app as an individual or a business.", False, "users"),
    ("Create your business profile",
     "Add your business name, description, city, service area, team size, languages, equipment and certifications.", False, "clipboard-list"),
    ("Add your services and categories",
     "Choose every service you offer from the same catalog customers browse.", False, "layout-grid"),
    ("Receive customer requests",
     "Matching requests reach you so you can accept or decline. Request delivery is rolling out with the app.", True, "mail"),
    ("Manage your information",
     "Update your profile, availability and details any time from the app.", False, "smartphone"),
]

# (title, text, icon)
TRUST_POINTS = [
    ("Real local businesses",
     "Providers come from real business listings in your city, not made-up profiles.", "map-pin"),
    ("Public ratings you can see",
     "Each provider shows its public rating and review count so you can compare before you reach out.", "star"),
    ("Matched to your job",
     "We match by the service you need, your location, and whether the provider is available.", "search"),
    ("Availability shown up front",
     "Providers can mark themselves available now or busy, so you don't chase people who can't help.", "clock"),
    ("Verification is on the way",
     "Identity, licence and insurance verification badges are planned. Until they launch, we never label a provider as verified.", "calendar-clock"),
]

# Icons for the decorative hero clusters.
HERO_CLUSTER_HOME = ["zap", "droplets", "spray-can", "hammer", "car", "briefcase", "trees", "truck", "camera"]
HERO_CLUSTER_PROVIDERS = ["users", "clipboard-list", "star", "message-circle", "layout-grid", "smartphone",
                          "map-pin", "mail", "clock"]
