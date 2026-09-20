"""Copy and metadata for the dedicated Edmonton SEO landing pages.

One dict entry per page; a single template (service_page.html) renders all
of them. Copy sticks to what Top-Link actually does today — no invented
provider names, ratings, reviews, prices, or verification claims.
"""

SEO_PAGES = {
    "electrician-edmonton": {
        "title": "Find an Electrician in Edmonton | Top-Link",
        "description": "Need an electrician in Edmonton? Top-Link matches you with local electrical providers for wiring, panel upgrades, lighting and repairs.",
        "h1": "Find a trusted electrician in Edmonton",
        "keyword": "electrician",
        "service_slug": "electrical",
        "breadcrumb": "Electrician",
        "intro": "From a dead outlet to a full panel upgrade, Top-Link helps Edmonton homeowners and businesses find local electrical providers, compare their public ratings, and connect through the app.",
        "covers": [
            "Wiring and rewiring",
            "Outlet, switch and lighting installation",
            "Breaker panel upgrades",
            "Electrical safety inspections",
            "Fault finding and emergency repairs",
        ],
        "when": [
            "Breakers keep tripping or lights flicker",
            "You are renovating and need new circuits",
            "You want a panel upgraded for an EV charger or hot tub",
            "You are buying or selling and want a safety check",
        ],
        "faqs": [
            ("How do I find an electrician in Edmonton with Top-Link?",
             "Choose Electrical Services in the app, tell us how urgent the job is and where you are, and we show local providers with their public ratings and availability."),
            ("Can I get an electrician the same day?",
             "Providers show whether they are available now. Choose the 'today' urgency and we prioritise providers who are."),
        ],
    },
    "plumber-edmonton": {
        "title": "Find a Plumber in Edmonton | Top-Link",
        "description": "Looking for a plumber in Edmonton? Top-Link connects you with local plumbing providers for leaks, drains, water heaters and emergencies.",
        "h1": "Find a trusted plumber in Edmonton",
        "keyword": "plumber",
        "service_slug": "plumbing",
        "breadcrumb": "Plumber",
        "intro": "Leaks and clogs don't wait. Top-Link helps you find Edmonton plumbing providers quickly, see their public ratings, and reach out through the app.",
        "covers": [
            "Leaky pipes and fixtures",
            "Clogged drains and toilets",
            "Water heater installation and repair",
            "Faucet, sink and toilet replacement",
            "Plumbing emergencies",
        ],
        "when": [
            "There is water where it shouldn't be",
            "Your water heater has stopped working",
            "Drains are slow or backing up",
            "You are renovating a kitchen or bathroom",
        ],
        "faqs": [
            ("How do I find a plumber in Edmonton with Top-Link?",
             "Choose Plumbing in the app, set your urgency and location, and we show local providers with their public ratings and availability."),
            ("What if it's an emergency?",
             "Pick the 'today' urgency. Providers who mark themselves available now are shown first."),
        ],
    },
    "cleaning-service-edmonton": {
        "title": "Cleaning Services in Edmonton | Top-Link",
        "description": "Find house and office cleaning services in Edmonton. Top-Link connects you with local cleaners for regular, deep and move-out cleaning.",
        "h1": "Find a cleaning service in Edmonton",
        "keyword": "cleaning service",
        "service_slug": "cleaning-services",
        "breadcrumb": "Cleaning Service",
        "intro": "Whether you want a one-time deep clean or a regular schedule, Top-Link helps you find Edmonton cleaning services, compare public ratings, and connect through the app.",
        "covers": [
            "Regular home and office cleaning",
            "Deep cleaning",
            "Move-in and move-out cleaning",
            "Recurring housekeeping",
        ],
        "when": [
            "You are moving in or out",
            "You are hosting and need a reset",
            "You want a recurring weekly or fortnightly clean",
            "The office needs regular upkeep",
        ],
        "faqs": [
            ("How do I find a cleaner in Edmonton with Top-Link?",
             "Choose Cleaning Services in the app, tell us when you need it and where, and we show local cleaners with their public ratings."),
            ("Can I compare cleaners before I get in touch?",
             "Yes. Each provider shows its public rating, review count and availability before you reach out."),
        ],
    },
    "contractor-edmonton": {
        "title": "Find a General Contractor in Edmonton | Top-Link",
        "description": "Need a contractor in Edmonton? Top-Link connects you with local general contractors for renovations, remodels and finishing work.",
        "h1": "Find a general contractor in Edmonton",
        "keyword": "general contractor",
        "service_slug": "construction-finishing",
        "breadcrumb": "Contractor",
        "intro": "Big projects need the right team. Top-Link helps you find Edmonton general contractors, compare their public ratings, and start the conversation in the app.",
        "covers": [
            "Full renovations and remodels",
            "General contracting",
            "New-build construction",
            "Finishing work: flooring, trim and fixtures",
        ],
        "when": [
            "You are planning a renovation or addition",
            "You need one contractor to coordinate several trades",
            "You want a quote for finishing work",
        ],
        "faqs": [
            ("How do I find a contractor in Edmonton with Top-Link?",
             "Choose Construction/Finishing (or a specific project like Kitchen Renovation) in the app, describe the job, and we show local providers."),
            ("Can I describe my project first?",
             "Yes. You can describe the job in your own words and Top-Link classifies it and finds matching providers."),
        ],
    },
    "home-improvement-edmonton": {
        "title": "Home Improvement Services in Edmonton | Top-Link",
        "description": "Home improvement in Edmonton made easy. Find local painters, flooring, roofing, carpentry and renovation pros through Top-Link.",
        "h1": "Home improvement services in Edmonton",
        "keyword": "home improvement",
        "service_slug": None,
        "related_service_slugs": [
            "painting", "flooring", "roofing", "carpentry", "drywall-decor",
            "kitchen-renovation", "bathroom-renovation", "home-repair",
        ],
        "breadcrumb": "Home Improvement",
        "intro": "Refresh a room, replace a roof, or remodel a whole kitchen. Top-Link brings Edmonton's home improvement providers together in one place, so you can compare public ratings and connect through the app.",
        "covers": [
            "Interior and exterior painting",
            "Flooring installation and refinishing",
            "Roof repair and replacement",
            "Carpentry, cabinetry and trim",
            "Drywall and finishing",
            "Kitchen and bathroom renovations",
        ],
        "when": [
            "You are updating a home before selling",
            "You want to tackle several projects with the right specialists",
            "You are not sure which trade you need",
        ],
        "faqs": [
            ("I'm not sure which trade I need. Where do I start?",
             "Describe the problem in your own words in the app. Top-Link works out the service you need and shows matching providers."),
            ("Do you cover more than Edmonton?",
             "Top-Link currently covers Edmonton, Calgary, Fort McMurray and Red Deer."),
        ],
    },
}

# service slug -> SEO page slug, for services that have a dedicated page
# (used so dropdown items link to the richer page instead of a generic one).
SEO_PAGE_BY_SERVICE = {
    page["service_slug"]: slug for slug, page in SEO_PAGES.items() if page["service_slug"]
}
