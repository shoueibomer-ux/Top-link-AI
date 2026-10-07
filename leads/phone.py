import re


def normalize_phone(raw: str) -> str:
    """Normalise a North American (or already international) number to E.164,
    the form Twilio uses for `From`/`To`. Returns "" when it can't be read as
    a phone number."""
    raw = (raw or "").strip()
    digits = re.sub(r"\D", "", raw)
    if raw.startswith("+"):
        return "+" + digits if 8 <= len(digits) <= 15 else ""
    if len(digits) == 10:
        return "+1" + digits
    if len(digits) == 11 and digits.startswith("1"):
        return "+" + digits
    return ""
