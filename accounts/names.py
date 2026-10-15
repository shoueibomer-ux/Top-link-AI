def public_name(full_name: str, fallback: str = "A client") -> str:
    """How a person is shown to others: first name and the initial of the last
    one ("Pat Provider" -> "Pat P."). Never an email address."""
    parts = (full_name or "").split()
    if not parts:
        return fallback
    if len(parts) == 1:
        return parts[0]
    return f"{parts[0]} {parts[-1][0].upper()}."
