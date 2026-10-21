final _postalCode = RegExp(r'^[A-Za-z]\d[A-Za-z][\s-]?\d[A-Za-z]\d$');

const kInvalidLocationMessage = 'Enter your postal code (like T5J 0N3) or your street address.';

/// What the client typed as where the job is, tidied up: a Canadian postal code becomes "T5J 0N3", an address has
/// its spaces collapsed. Null when it is neither (too short to be an address, or empty).
String? normalizeLocation(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (_postalCode.hasMatch(text)) {
    final code = text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }
  if (text.length < 5 || text.length > 120) return null;
  return text;
}
