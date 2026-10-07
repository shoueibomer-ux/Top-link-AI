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


_NORTH_AMERICAN = re.compile(r"\+1[2-9]\d{2}[2-9]\d{6}")
_PHONE_CHARACTERS = re.compile(r"\+?[\d\s().\-]+")


def normalize_north_american_phone(raw) -> str:
    """The strict form used for client phone numbers: a Canadian / North
    American number (10 digits, or 11 starting with 1, optionally written with
    a leading +) returned as +1XXXXXXXXXX, or "" if it isn't one.

    Beyond the digit count it requires the area code and exchange to start
    with 2-9, as every real NANP number does, and only digits, spaces, dots,
    dashes and brackets (plus one leading +). Anything else - letters,
    extensions, another country's number, a non-string - is rejected."""
    if not isinstance(raw, str) or not _PHONE_CHARACTERS.fullmatch(raw.strip()):
        return ""
    number = normalize_phone(raw)
    return number if _NORTH_AMERICAN.fullmatch(number) else ""
