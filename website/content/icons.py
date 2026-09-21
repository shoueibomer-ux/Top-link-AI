"""Which Lucide icon represents each service and sector on the website.

Keyed by catalog.Service.slug / website.Sector.slug. Website-owned (the app
uses Material icon names for its own UI). Unknown slugs fall back to a
generic icon rather than failing.
"""

SERVICE_ICONS = {
    # Trades & Professional Services
    "electrical": "zap",
    "plumbing": "droplets",
    "hvac": "fan",
    "carpentry": "hammer",
    "painting": "paintbrush",
    "general-maintenance": "wrench",
    "construction-finishing": "hard-hat",
    "drywall-decor": "paint-roller",
    "metalwork-aluminum": "flame",
    "glass-mirrors": "frame",
    "flooring": "layers",
    "roofing": "house",
    "concrete-work": "brick-wall",
    "kitchen-renovation": "cooking-pot",
    "bathroom-renovation": "bath",
    # Home Services
    "cleaning-services": "spray-can",
    "moving-services": "truck",
    "furniture-assembly": "armchair",
    "home-repair": "drill",
    "delivery-services": "package",
    "storage-services": "warehouse",
    # Automotive
    "mechanic-services": "car",
    "car-wash": "car-front",
    "tire-repair": "circle-dot",
    "towing-services": "siren",
    # Business
    "accounting-services": "calculator",
    "marketing-services": "megaphone",
    "website-design": "monitor",
    "it-services": "cpu",
    "legal-services": "scale",
    # Events
    "photography": "camera",
    "event-decoration": "gift",
    "event-planning": "calendar-days",
    "sound-lighting": "speaker",
    "catering": "utensils-crossed",
    "security-services": "shield-check",
    # Personal
    "barber-services": "scissors",
    "beauty-services": "sparkles",
    "personal-training": "dumbbell",
    "tutoring": "graduation-cap",
    # Outdoor
    "lawn-care": "sprout",
    "snow-removal": "snowflake",
    "tree-services": "tree-pine",
    "landscaping": "flower-2",
}

SECTOR_ICONS = {
    "home-services": "house",
    "construction-renovation": "hard-hat",
    "automotive-services": "car",
    "business-services": "briefcase",
    "outdoor-services": "trees",
    "moving-delivery": "truck",
    "events-personal": "party-popper",
}

# Home-improvement SEO page has no single service; it gets the sector icon.
SEO_PAGE_ICONS = {"home-improvement-edmonton": "house"}
