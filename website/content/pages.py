"""Static marketing copy shared across website pages."""

JOURNEY_STEPS = [
    ("Search", "You look for a local service on Google."),
    ("Top-Link", "You land on the Top-Link website."),
    ("Choose", "Pick the service category you need."),
    ("Select", "Compare providers and pick the right one."),
    ("Request", "Send your service request."),
    ("Connect", "Continue the conversation in the Top-Link app."),
]

HOW_IT_WORKS = [
    ("Choose a service", "Browse the sectors and pick what you need, or describe the job in your own words."),
    ("Tell us the details", "Say how urgent it is and where you are located."),
    ("Compare providers", "See local providers with their public ratings, review counts and availability."),
    ("Connect in the app", "Reach out to the provider you like and keep everything in one place."),
]

# (title, description, coming_soon)
PROVIDER_FEATURES = [
    ("Register as a provider",
     "Create a business account in the Top-Link app as an individual or a business.", False),
    ("Create your business profile",
     "Add your business name, description, city, service area, team size, languages, equipment and certifications.", False),
    ("Add your services and categories",
     "Choose every service you offer from the same catalog customers browse.", False),
    ("Receive customer requests",
     "Matching requests reach you so you can accept or decline. Request delivery is rolling out with the app.", True),
    ("Manage your information",
     "Update your profile, availability and details any time from the app.", False),
]

TRUST_POINTS = [
    ("Real local businesses",
     "Providers come from real business listings in your city, not made-up profiles."),
    ("Public ratings you can see",
     "Each provider shows its public rating and review count so you can compare before you reach out."),
    ("Matched to your job",
     "We match by the service you need, your location, and whether the provider is available."),
    ("Availability shown up front",
     "Providers can mark themselves available now or busy, so you don't chase people who can't help."),
    ("Verification is on the way",
     "Identity, licence and insurance verification badges are planned. Until they launch, we never label a provider as verified."),
]
