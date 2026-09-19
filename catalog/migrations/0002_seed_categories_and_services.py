from django.db import migrations

# Seed data for the marketplace build plan's "Phase 1B: Dynamic Categories &
# Services". The 6 groups and their named services come from the product
# spec; the first group also folds in the 4 legacy categories that existed
# before this migration (construction-finishing, drywall-decor,
# metalwork-aluminum, glass-mirrors) so nothing already stored against those
# slugs (ProviderMatch.category, ServiceRequest.category,
# ProviderBusinessProfile.categories) breaks. Every service slug that
# overlaps a pre-existing flat category (plumbing, electrical, carpentry,
# hvac, painting, and the 4 legacy ones above) reuses that exact slug.
CATALOG = [
    {
        "name": "Trades & Professional Services",
        "slug": "trades-professional",
        "icon_name": "construction",
        "services": [
            {
                "name": "Plumbing",
                "slug": "plumbing",
                "icon_name": "plumbing",
                "worker_noun": "plumbers",
                "google_places_query": "plumber",
                "what_we_cover": "We cover leaky pipes, clogged drains, water heater installation and repair, fixture replacements, toilet and faucet repairs, and general plumbing emergencies.",
            },
            {
                "name": "Electrical Services",
                "slug": "electrical",
                "icon_name": "electrical_services",
                "worker_noun": "electricians",
                "google_places_query": "electrician",
                "what_we_cover": "We cover wiring and rewiring, outlet and switch installation, breaker panel upgrades, lighting installation, and electrical safety inspections and repairs.",
            },
            {
                "name": "HVAC",
                "slug": "hvac",
                "icon_name": "ac_unit",
                "worker_noun": "HVAC technicians",
                "google_places_query": "HVAC contractor",
                "what_we_cover": "We cover furnace and air conditioner repair and installation, heating and cooling system maintenance, ventilation and ductwork, and thermostat setup.",
            },
            {
                "name": "Carpentry",
                "slug": "carpentry",
                "icon_name": "carpenter",
                "worker_noun": "carpenters",
                "google_places_query": "carpenter",
                "what_we_cover": "We cover custom cabinetry, framing, furniture building and repair, deck construction, trim work, and other wood-based construction projects.",
            },
            {
                "name": "Painting",
                "slug": "painting",
                "icon_name": "format_paint",
                "worker_noun": "painters",
                "google_places_query": "painting contractor",
                "what_we_cover": "We cover interior and exterior painting, wall and trim finishing, touch-ups, surface preparation, and color consultation for homes and businesses.",
            },
            {
                "name": "General Maintenance",
                "slug": "general-maintenance",
                "icon_name": "handyman",
                "worker_noun": "maintenance technicians",
                "google_places_query": "handyman service",
                "what_we_cover": "We cover general handyman work, minor repairs, fixture touch-ups, and small maintenance jobs around the home or business.",
            },
            {
                "name": "Construction/Finishing",
                "slug": "construction-finishing",
                "icon_name": "construction",
                "worker_noun": "contractors",
                "google_places_query": "general contractor",
                "what_we_cover": "We cover full renovations, remodels, general contracting, new-build construction, and finishing work like flooring, trim, and fixtures.",
            },
            {
                "name": "Drywall & Decor",
                "slug": "drywall-decor",
                "icon_name": "home_repair_service",
                "worker_noun": "drywall and decor specialists",
                "google_places_query": "drywall contractor",
                "what_we_cover": "We cover drywall installation and repair, ceiling work, molding and trim, texture and finishing, and general interior decor installation.",
            },
            {
                "name": "Metalwork/Aluminum",
                "slug": "metalwork-aluminum",
                "icon_name": "precision_manufacturing",
                "worker_noun": "metalworkers",
                "google_places_query": "metal fabrication welding shop",
                "what_we_cover": "We cover welding, custom railings and gates, aluminum and steel fabrication, structural metalwork, and repair of metal fixtures.",
            },
            {
                "name": "Glass & Mirrors",
                "slug": "glass-mirrors",
                "icon_name": "window",
                "worker_noun": "glass and mirror specialists",
                "google_places_query": "glass and mirror shop",
                "what_we_cover": "We cover window replacement and repair, custom mirror installation, glass shower doors and enclosures, and storefront or display glass work.",
            },
        ],
    },
    {
        "name": "Home Services",
        "slug": "home-services",
        "icon_name": "home",
        "services": [
            {
                "name": "Cleaning Services",
                "slug": "cleaning-services",
                "icon_name": "cleaning_services",
                "worker_noun": "cleaners",
                "google_places_query": "house cleaning service",
                "what_we_cover": "We cover home and office cleaning, deep cleaning, move-in/move-out cleaning, and recurring housekeeping.",
            },
            {
                "name": "Moving Services",
                "slug": "moving-services",
                "icon_name": "local_shipping",
                "worker_noun": "movers",
                "google_places_query": "moving company",
                "what_we_cover": "We cover local and long-distance moves, packing and unpacking, and furniture transport.",
            },
            {
                "name": "Furniture Assembly",
                "slug": "furniture-assembly",
                "icon_name": "chair",
                "worker_noun": "assembly technicians",
                "google_places_query": "furniture assembly service",
                "what_we_cover": "We cover flat-pack furniture assembly, disassembly for moves, and furniture installation.",
            },
            {
                "name": "Home Repair",
                "slug": "home-repair",
                "icon_name": "build",
                "worker_noun": "repair technicians",
                "google_places_query": "home repair service",
                "what_we_cover": "We cover general home repairs, fixture fixes, and small household jobs that don't need a specialist trade.",
            },
        ],
    },
    {
        "name": "Automotive Services",
        "slug": "automotive-services",
        "icon_name": "directions_car",
        "services": [
            {
                "name": "Mechanic Services",
                "slug": "mechanic-services",
                "icon_name": "car_repair",
                "worker_noun": "mechanics",
                "google_places_query": "auto mechanic",
                "what_we_cover": "We cover general auto repair, diagnostics, oil changes, brakes, and routine maintenance.",
            },
            {
                "name": "Car Wash",
                "slug": "car-wash",
                "icon_name": "local_car_wash",
                "worker_noun": "car wash providers",
                "google_places_query": "car wash",
                "what_we_cover": "We cover exterior and interior car washing, detailing, and waxing.",
            },
            {
                "name": "Tire Repair",
                "slug": "tire-repair",
                "icon_name": "build_circle",
                "worker_noun": "tire technicians",
                "google_places_query": "tire shop",
                "what_we_cover": "We cover flat tire repair, tire replacement, rotations, and balancing.",
            },
            {
                "name": "Towing Services",
                "slug": "towing-services",
                "icon_name": "local_shipping",
                "worker_noun": "tow operators",
                "google_places_query": "towing service",
                "what_we_cover": "We cover roadside towing, vehicle recovery, and emergency roadside assistance.",
            },
        ],
    },
    {
        "name": "Business Services",
        "slug": "business-services",
        "icon_name": "business_center",
        "services": [
            {
                "name": "Accounting Services",
                "slug": "accounting-services",
                "icon_name": "calculate",
                "worker_noun": "accountants",
                "google_places_query": "accounting firm",
                "what_we_cover": "We cover bookkeeping, tax preparation, payroll, and general business accounting.",
            },
            {
                "name": "Marketing Services",
                "slug": "marketing-services",
                "icon_name": "campaign",
                "worker_noun": "marketing specialists",
                "google_places_query": "marketing agency",
                "what_we_cover": "We cover social media management, advertising campaigns, branding, and marketing strategy.",
            },
            {
                "name": "Website Design",
                "slug": "website-design",
                "icon_name": "language",
                "worker_noun": "web designers",
                "google_places_query": "web design agency",
                "what_we_cover": "We cover website design, development, e-commerce setup, and website maintenance.",
            },
            {
                "name": "IT Services",
                "slug": "it-services",
                "icon_name": "computer",
                "worker_noun": "IT technicians",
                "google_places_query": "IT services company",
                "what_we_cover": "We cover IT support, network setup, computer repair, and technical troubleshooting.",
            },
        ],
    },
    {
        "name": "Events Services",
        "slug": "events-services",
        "icon_name": "celebration",
        "services": [
            {
                "name": "Photography",
                "slug": "photography",
                "icon_name": "camera_alt",
                "worker_noun": "photographers",
                "google_places_query": "photographer",
                "what_we_cover": "We cover event photography, portraits, and photo editing for weddings, parties, and corporate events.",
            },
            {
                "name": "Event Decoration",
                "slug": "event-decoration",
                "icon_name": "celebration",
                "worker_noun": "event decorators",
                "google_places_query": "event decorator",
                "what_we_cover": "We cover event decor, balloon and floral arrangements, and themed setups for parties and weddings.",
            },
            {
                "name": "Event Planning",
                "slug": "event-planning",
                "icon_name": "event",
                "worker_noun": "event planners",
                "google_places_query": "event planner",
                "what_we_cover": "We cover full event planning and coordination, vendor booking, and day-of event management.",
            },
            {
                "name": "Sound & Lighting Services",
                "slug": "sound-lighting",
                "icon_name": "speaker",
                "worker_noun": "sound and lighting technicians",
                "google_places_query": "event sound and lighting rental",
                "what_we_cover": "We cover sound system and lighting rental and setup for events, parties, and venues.",
            },
        ],
    },
    {
        "name": "Personal Services",
        "slug": "personal-services",
        "icon_name": "person",
        "services": [
            {
                "name": "Barber Services",
                "slug": "barber-services",
                "icon_name": "content_cut",
                "worker_noun": "barbers",
                "google_places_query": "barber shop",
                "what_we_cover": "We cover haircuts, beard trims, and grooming services for men.",
            },
            {
                "name": "Beauty Services",
                "slug": "beauty-services",
                "icon_name": "spa",
                "worker_noun": "beauty professionals",
                "google_places_query": "beauty salon",
                "what_we_cover": "We cover hair styling, makeup, skincare, nails, and other beauty treatments.",
            },
            {
                "name": "Personal Training",
                "slug": "personal-training",
                "icon_name": "fitness_center",
                "worker_noun": "personal trainers",
                "google_places_query": "personal trainer",
                "what_we_cover": "We cover one-on-one and group fitness training, workout plans, and nutrition coaching.",
            },
            {
                "name": "Tutoring",
                "slug": "tutoring",
                "icon_name": "school",
                "worker_noun": "tutors",
                "google_places_query": "tutoring service",
                "what_we_cover": "We cover academic tutoring, test prep, and skill-building lessons for students of all ages.",
            },
        ],
    },
]


def seed_catalog(apps, schema_editor):
    Category = apps.get_model("catalog", "Category")
    Service = apps.get_model("catalog", "Service")

    for category_order, category_data in enumerate(CATALOG):
        category = Category.objects.create(
            name=category_data["name"],
            slug=category_data["slug"],
            icon_name=category_data["icon_name"],
            display_order=category_order,
        )
        for service_order, service_data in enumerate(category_data["services"]):
            Service.objects.create(
                category=category,
                name=service_data["name"],
                slug=service_data["slug"],
                icon_name=service_data["icon_name"],
                what_we_cover=service_data["what_we_cover"],
                worker_noun=service_data["worker_noun"],
                google_places_query=service_data["google_places_query"],
                display_order=service_order,
            )


def unseed_catalog(apps, schema_editor):
    Category = apps.get_model("catalog", "Category")
    Category.objects.filter(slug__in=[c["slug"] for c in CATALOG]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("catalog", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed_catalog, unseed_catalog),
    ]
