from django.db import migrations

# Clustered around the same demo location (Edmonton) the Flutter app sends
# until the app collects a real one.
PROVIDERS = [
    ("Ahmed Plumbing Co.", "business", ["plumbing"], 53.5461, -113.4938, 4.6),
    ("QuickFix Plumbers", "business", ["plumbing"], 53.6000, -113.4500, 3.8),
    ("Sara's Electric", "business", ["electrical"], 53.5501, -113.5001, 4.9),
    ("Bright Spark Electrical", "business", ["electrical"], 53.5395, -113.4870, 4.3),
    ("Karim (freelance carpenter)", "individual", ["carpentry"], 53.5480, -113.4900, 0.0),
    ("CoolBreeze HVAC", "business", ["hvac"], 53.5430, -113.4850, 4.7),
    ("Premier Painting Co.", "business", ["painting"], 53.5470, -113.4990, 4.4),
    ("Solid Build Construction", "business", ["construction-finishing"], 53.5510, -113.4800, 4.1),
    ("Smooth Wall Drywall & Decor", "business", ["drywall-decor"], 53.5420, -113.4950, 4.0),
    ("IronCraft Metalworks", "business", ["metalwork-aluminum"], 53.5550, -113.4700, 4.5),
    ("Crystal Clear Glass & Mirrors", "business", ["glass-mirrors"], 53.5390, -113.4920, 4.2),
]


def seed_providers(apps, schema_editor):
    Category = apps.get_model("matching", "Category")
    Profile = apps.get_model("matching", "Profile")

    for name, role, categories, lat, lng, rating in PROVIDERS:
        profile = Profile.objects.create(
            name=name,
            role=role,
            description=f"Serving the Edmonton area. Specializes in {', '.join(categories)}.",
            lat=lat,
            lng=lng,
            available=True,
            rating=rating,
        )
        for category_name in categories:
            category, _ = Category.objects.get_or_create(name=category_name)
            profile.categories.add(category)


def remove_seeded_providers(apps, schema_editor):
    Profile = apps.get_model("matching", "Profile")
    Profile.objects.filter(name__in=[p[0] for p in PROVIDERS]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("matching", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(seed_providers, remove_seeded_providers),
    ]
