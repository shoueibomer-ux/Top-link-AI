from django.db import migrations

# (sector name, slug, blurb, [(display label, catalog.Service slug), ...])
# Landscaping is listed under two sectors but is ONE catalog.Service.
SECTORS = [
    ("Home Services", "home-services", "Everyday help for your home.", [
        ("Electrician", "electrical"),
        ("Plumber", "plumbing"),
        ("HVAC / Heating & Cooling", "hvac"),
        ("Cleaning Services", "cleaning-services"),
        ("Handyman", "general-maintenance"),
        ("Painting", "painting"),
        ("Flooring", "flooring"),
        ("Roofing", "roofing"),
        ("Landscaping", "landscaping"),
    ]),
    ("Construction & Renovation", "construction-renovation", "Build, remodel and finish.", [
        ("General Contractor", "construction-finishing"),
        ("Home Renovation", "construction-finishing"),
        ("Kitchen Renovation", "kitchen-renovation"),
        ("Bathroom Renovation", "bathroom-renovation"),
        ("Drywall", "drywall-decor"),
        ("Concrete Work", "concrete-work"),
    ]),
    ("Automotive Services", "automotive-services", "Keep your vehicle moving.", [
        ("Auto Repair", "mechanic-services"),
        ("Mobile Mechanic", "mechanic-services"),
        ("Car Cleaning", "car-wash"),
        ("Towing Service", "towing-services"),
    ]),
    ("Business Services", "business-services", "Professional help for your business.", [
        ("Accounting", "accounting-services"),
        ("Legal Services", "legal-services"),
        ("Marketing", "marketing-services"),
        ("IT Support", "it-services"),
        ("Website Development", "website-design"),
    ]),
    ("Outdoor Services", "outdoor-services", "Yards, lawns, trees and snow.", [
        ("Lawn Care", "lawn-care"),
        ("Snow Removal", "snow-removal"),
        ("Tree Services", "tree-services"),
        ("Landscaping", "landscaping"),
    ]),
    ("Moving & Delivery", "moving-delivery", "Move it, deliver it, store it.", [
        ("Moving Companies", "moving-services"),
        ("Furniture Assembly", "furniture-assembly"),
        ("Delivery Services", "delivery-services"),
        ("Storage Services", "storage-services"),
    ]),
    ("Events & Personal Services", "events-personal", "Make the occasion count.", [
        ("Event Planning", "event-planning"),
        ("Photography", "photography"),
        ("Catering", "catering"),
        ("Security Services", "security-services"),
    ]),
]


def seed(apps, schema_editor):
    Sector = apps.get_model("website", "Sector")
    SectorItem = apps.get_model("website", "SectorItem")
    Service = apps.get_model("catalog", "Service")

    for order, (name, slug, blurb, items) in enumerate(SECTORS):
        sector, _ = Sector.objects.get_or_create(
            slug=slug, defaults={"name": name, "blurb": blurb, "display_order": order}
        )
        for item_order, (label, service_slug) in enumerate(items):
            service = Service.objects.get(slug=service_slug)
            SectorItem.objects.get_or_create(
                sector=sector, label=label,
                defaults={"service": service, "display_order": item_order},
            )


def unseed(apps, schema_editor):
    Sector = apps.get_model("website", "Sector")
    Sector.objects.filter(slug__in=[s[1] for s in SECTORS]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("website", "0001_initial"),
        ("catalog", "0003_extended_services_and_outdoor"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
