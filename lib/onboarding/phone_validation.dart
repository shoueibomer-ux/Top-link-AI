import 'package:flutter/services.dart';

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

/// How a North American number reads on screen: "+17805550100" -> "(780) 555-0100". Anything that is not a
/// 10-digit national number (with or without +1) comes back unchanged.
String formatPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('1')) digits = digits.substring(1);
  if (digits.length != 10) return raw;
  return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
}

String _formatPartial(String digits) {
  if (digits.isEmpty) return '';
  if (digits.length <= 3) return '($digits';
  if (digits.length <= 6) return '(${digits.substring(0, 3)}) ${digits.substring(3)}';
  return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
}

/// Formats a phone number as it is typed ("7805550100" -> "(780) 555-0100"). A leading 1 (the country code) is
/// dropped, since no area code starts with 1. Too many digits are left as typed. Deleting a bracket, space or dash removes the digit before it
/// instead of snapping back. [normalizeNorthAmericanPhone] reads the result as before.
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

  static String _digits(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('1') ? digits.substring(1) : digits;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = _digits(newValue.text);
    // More than 10 digits is not a number to tidy up (cutting it short could save a different number): leave what
    // was typed so the form can say it is not valid.
    if (digits.length > 10) return newValue;
    final deleting = newValue.text.length < oldValue.text.length;
    if (deleting && digits == _digits(oldValue.text) && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final text = _formatPartial(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
