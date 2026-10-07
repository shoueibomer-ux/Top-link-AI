/// Shown under the phone field and returned by the backend for the same
/// problem (provider_search.views.ServiceRequestCreateView.INVALID_PHONE_MESSAGE).
const kInvalidPhoneMessage = 'Enter a valid Canadian or North American phone number, for example 780 555 0100.';

final _allowedCharacters = RegExp(r'^\+?[\d\s().\-]+$');
final _nationalNumber = RegExp(r'^[2-9]\d{2}[2-9]\d{6}$');

/// The client's number as +1XXXXXXXXXX, or null if it isn't a Canadian / North
/// American number: 10 digits, or 11 starting with 1, optionally written with
/// a leading +. The area code and exchange must start with 2-9, and only
/// digits, spaces, dots, dashes and brackets are allowed.
///
/// Mirrors leads.phone.normalize_north_american_phone on the backend, which
/// makes the same decision again before anything is stored.
String? normalizeNorthAmericanPhone(String raw) {
  final text = raw.trim();
  if (!_allowedCharacters.hasMatch(text)) return null;
  final digits = text.replaceAll(RegExp(r'\D'), '');

  final String national;
  if (digits.length == 10 && !text.startsWith('+')) {
    national = digits;
  } else if (digits.length == 11 && digits.startsWith('1')) {
    national = digits.substring(1);
  } else {
    return null;
  }
  return _nationalNumber.hasMatch(national) ? '+1$national' : null;
}
