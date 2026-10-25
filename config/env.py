"""Cleans the process environment before settings read it (no Django imports, so settings can use it)."""


def strip_environ(environ) -> list[str]:
    """Strips leading/trailing whitespace and newlines from every value in `environ`, in place.

    Values pasted into Render's form can carry a trailing newline ("smtp-relay.brevo.com\\n\\n" broke SMTP).
    Done on os.environ itself so every reader gets the clean value: settings, the modules that read
    ANTHROPIC_API_KEY or WEBSITE_CONTACT_EMAIL directly, and libraries such as dj_database_url.
    Returns the names that changed (never the values, which may be secrets).
    """
    changed = []
    for name, value in list(environ.items()):
        stripped = value.strip()
        if stripped != value:
            environ[name] = stripped
            changed.append(name)
    return changed
