import json

from django.core.management.base import BaseCommand

from providers.audit import build_report, read_only_guard


class Command(BaseCommand):
    help = (
        "READ-ONLY inventory of every kind of provider record (hand-added, email/password, Google sign-in), their "
        "lead offers, duplicates and data problems, to plan merging them into one model. Changes nothing."
    )

    def add_arguments(self, parser):
        parser.add_argument("--json", action="store_true", help="Print the report as JSON instead of text.")
        parser.add_argument(
            "--details", action="store_true",
            help="Show full phone numbers and emails where duplicates are listed (masked by default).",
        )

    def handle(self, *args, **options):
        with read_only_guard():
            report = build_report(show_details=options["details"])
        if options["json"]:
            self.stdout.write(json.dumps(report, indent=2, default=str))
        else:
            self.stdout.write(render_text(report))


def _lines(title, mapping, indent="  "):
    out = [title]
    for key, value in mapping.items():
        label = key.replace("_", " ")
        out.append(f"{indent}{label}: {value}")
    return out


def render_text(report: dict) -> str:
    lines = [
        "PROVIDER AUDIT (read-only: nothing was changed)",
        "=" * 60,
        "",
        *_lines("Hand-added providers (leads.Provider)", report["leads_provider"]),
        "",
        *_lines("Lead offers", {k: v for k, v in report["lead_offers"].items() if k != "by_status"}),
        *_lines("  by status", report["lead_offers"]["by_status"], indent="    "),
        "",
        *_lines("Accounts", report["accounts"]),
        "",
        *_lines("Email/password provider profiles (accounts.ProviderBusinessProfile)", report["business_profiles"]),
        "",
        *_lines(
            "Google sign-in provider profiles (providers.ProviderProfile)",
            {k: v for k, v in report["provider_profiles"].items() if k != "by_status"},
        ),
        *_lines("  by status", report["provider_profiles"]["by_status"], indent="    "),
        "",
        *_lines("Not part of the merge", report["not_part_of_the_merge"]),
        "",
        "Accounts with both an email/password profile and a Google profile: "
        f"{report['users_with_both_a_business_profile_and_a_provider_profile']}",
        "",
        f"Possible duplicates ({len(report['duplicates'])})",
    ]
    for dup in report["duplicates"]:
        kind = "same account" if dup["same_account"] else "DIFFERENT accounts or no account"
        lines.append(f"  {dup['matched_on']}  [{kind}]")
        lines.append(f"    {', '.join(dup['records'])}")
    lines += ["", "What to deal with"]
    if not report["notes"]:
        lines.append("  Nothing flagged.")
    for note in report["notes"]:
        lines.append(f"  [{note['level'].upper()}] {note['text']}")
    return "\n".join(lines)
