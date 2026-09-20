from django.db import migrations

# Adds the services (and the Outdoor Services category) needed so every item
# on the marketing website's sector menu resolves to a real backend Service.
# Uses get_or_create by slug, so re-running is safe and never overwrites
# admin edits made to an existing row.
NEW_SERVICES = [
    # (category slug, slug, name, icon, worker_noun, places query, what_we_cover)
    ("trades-professional", "flooring", "Flooring", "layers", "flooring installers", "flooring contractor",
     "We cover hardwood, laminate, vinyl, tile, and carpet installation, refinishing, and floor repair."),
    ("trades-professional", "roofing", "Roofing", "roofing", "roofers", "roofing contractor",
     "We cover roof repair and replacement, shingles, flashing, eavestroughs, and leak and storm-damage repair."),
    ("trades-professional", "concrete-work", "Concrete Work", "foundation", "concrete contractors", "concrete contractor",
     "We cover driveways, sidewalks, patios, foundations, slabs, and concrete repair and finishing."),
    ("trades-professional", "kitchen-renovation", "Kitchen Renovation", "kitchen", "kitchen renovators", "kitchen renovation contractor",
     "We cover full kitchen remodels, cabinetry and countertop installation, backsplashes, and layout redesign."),
    ("trades-professional", "bathroom-renovation", "Bathroom Renovation", "bathtub", "bathroom renovators", "bathroom renovation contractor",
     "We cover full bathroom remodels, tub and shower installation, tiling, vanities, and plumbing fixture upgrades."),
    ("home-services", "delivery-services", "Delivery Services", "delivery_dining", "delivery drivers", "courier delivery service",
     "We cover same-day and scheduled local delivery, courier runs, and large-item delivery."),
    ("home-services", "storage-services", "Storage Services", "warehouse", "storage providers", "self storage",
     "We cover short- and long-term storage units, secure storage for moves, and pickup-and-store services."),
    ("business-services", "legal-services", "Legal Services", "gavel", "lawyers", "law firm",
     "We cover lawyers and paralegals for contracts, real estate, business formation, family, and general legal advice."),
    ("events-services", "catering", "Catering", "restaurant", "caterers", "catering service",
     "We cover event and corporate catering, buffet and plated service, and custom menus."),
    ("events-services", "security-services", "Security Services", "security", "security professionals", "security guard company",
     "We cover event security, guards, crowd management, and alarm and monitoring services."),
    ("outdoor-services", "lawn-care", "Lawn Care", "grass", "lawn care specialists", "lawn care service",
     "We cover mowing, edging, fertilizing, aeration, weed control, and seasonal lawn maintenance."),
    ("outdoor-services", "snow-removal", "Snow Removal", "snowing", "snow removal crews", "snow removal service",
     "We cover driveway and sidewalk snow clearing, seasonal plowing contracts, and ice control."),
    ("outdoor-services", "tree-services", "Tree Services", "forest", "arborists", "tree service",
     "We cover tree trimming and removal, stump grinding, emergency storm cleanup, and tree health care."),
    ("outdoor-services", "landscaping", "Landscaping", "yard", "landscapers", "landscaping company",
     "We cover landscape design, planting, sod, retaining walls, patios, and full yard makeovers."),
]


def add_services(apps, schema_editor):
    Category = apps.get_model("catalog", "Category")
    Service = apps.get_model("catalog", "Service")

    outdoor, _ = Category.objects.get_or_create(
        slug="outdoor-services",
        defaults={
            "name": "Outdoor Services",
            "icon_name": "park",
            "display_order": Category.objects.count(),
        },
    )
    categories = {c.slug: c for c in Category.objects.all()}
    categories["outdoor-services"] = outdoor

    for category_slug, slug, name, icon, noun, query, cover in NEW_SERVICES:
        category = categories[category_slug]
        Service.objects.get_or_create(
            slug=slug,
            defaults={
                "category": category,
                "name": name,
                "icon_name": icon,
                "worker_noun": noun,
                "google_places_query": query,
                "what_we_cover": cover,
                "display_order": Service.objects.filter(category=category).count(),
            },
        )


def remove_services(apps, schema_editor):
    Category = apps.get_model("catalog", "Category")
    Service = apps.get_model("catalog", "Service")
    Service.objects.filter(slug__in=[row[1] for row in NEW_SERVICES]).delete()
    Category.objects.filter(slug="outdoor-services").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("catalog", "0002_seed_categories_and_services"),
    ]

    operations = [
        migrations.RunPython(add_services, remove_services),
    ]
