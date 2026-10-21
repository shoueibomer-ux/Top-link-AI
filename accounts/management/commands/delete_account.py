from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from accounts.deletion import AccountNotDeletable, delete_account
from accounts.models import AccountDeletion


class Command(BaseCommand):
    help = (
        "Deletes one account on request (someone emailed us): anonymises their personal data and removes their chats, "
        "photos and push tokens. Same as the app's \"Delete my account\". Cannot be undone."
    )

    def add_arguments(self, parser):
        parser.add_argument("--email", required=True, help="The email on the account.")
        parser.add_argument("--yes", action="store_true", help="Really do it (without this it only says what it would delete).")

    def handle(self, *args, **options):
        User = get_user_model()
        user = User.objects.filter(email__iexact=options["email"].strip()).first()
        if user is None:
            raise CommandError("No account has that email.")
        role = getattr(getattr(user, "profile", None), "role", "no role")
        if not options["yes"]:
            self.stdout.write(f"Would delete the {role} account #{user.pk}. Run again with --yes to do it.")
            return
        try:
            summary = delete_account(user, via=AccountDeletion.VIA_COMMAND)
        except AccountNotDeletable as exc:
            raise CommandError(str(exc))
        if summary.already_deleted:
            self.stdout.write("That account was already deleted.")
            return
        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted account #{user.pk}: {summary.conversations} chat(s), {summary.messages} message(s), "
                f"{summary.photos_deleted} photo(s) removed, {summary.photos_waiting} photo(s) queued for retry."
            )
        )
