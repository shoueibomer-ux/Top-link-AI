import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';
import 'location_validation.dart';

/// Finds where the phone is and, if it can, the postal code there. Both are replaced in tests.
/// Throws a message for the person ("Location services are turned off.") when it can't.
typedef LocateDevice = Future<({double latitude, double longitude})> Function();
typedef PostalCodeFor = Future<String?> Function(double latitude, double longitude);

Future<({double latitude, double longitude})> locateDevice() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw 'Location services are turned off.';
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw 'Location permission was denied.';
  }
  try {
    // A phone indoors can wait a long time for a fix: give up after a little and let the person type instead.
    final position = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));
    return (latitude: position.latitude, longitude: position.longitude);
  } on TimeoutException {
    throw 'It took too long to find you.';
  }
}

Future<String?> postalCodeForPosition(double latitude, double longitude) async {
  try {
    for (final place in await Geocoding().placemarkFromCoordinates(latitude, longitude)) {
      final code = normalizeLocation(place.postalCode ?? '');
      if (code != null) return code;
    }
  } catch (_) {
    // No geocoder on this phone, or no network: the person types it instead.
  }
  return null;
}

/// Where is the job? "Use my current location" fills in the postal code for where the phone is; otherwise the
/// person types a postal code or an address. Coordinates are never shown.
class LocationStep extends StatefulWidget {
  const LocationStep({
    super.key,
    required this.location,
    required this.onLocationChanged,
    this.locate = locateDevice,
    this.postalCodeFor = postalCodeForPosition,
  });

  final String location;
  final ValueChanged<String> onLocationChanged;
  final LocateDevice locate;
  final PostalCodeFor postalCodeFor;

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  late final _controller = TextEditingController(text: widget.location);

  bool _isLocating = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _statusMessage = null;
    });
    try {
      final position = await widget.locate();
      final code = await widget.postalCodeFor(position.latitude, position.longitude);
      if (!mounted) return;
      if (code != null) {
        _controller.text = code;
        widget.onLocationChanged(code);
        setState(() {
          _statusIsError = false;
          _statusMessage = 'We found your postal code. Change it if it is not right.';
        });
      } else {
        setState(() {
          _statusIsError = false;
          _statusMessage = "We found you, but not your postal code. Please type your postal code or address below.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not get your location: $e Type your postal code or address instead.';
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _controller.text.trim().isNotEmpty;
    final invalid = typed && normalizeLocation(_controller.text) == null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where is the job?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          Text(
            "We'll use this to find providers near you. Providers only see it once they accept your request.",
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          Pressable(
            enabled: !_isLocating,
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('use-current-location'),
                onPressed: _isLocating ? null : _useCurrentLocation,
                icon: _isLocating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, color: AppColors.turquoise),
                label: Text(
                  _isLocating ? 'Finding your location…' : 'Use my current location',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  side: const BorderSide(color: AppColors.turquoise),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                ),
              ),
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              key: const Key('location-status'),
              style: TextStyle(fontSize: 13, height: 1.4, color: _statusIsError ? Colors.red.shade700 : AppColors.turquoise),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'OR TYPE A POSTAL CODE OR ADDRESS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppColors.navy.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('location-field'),
            controller: _controller,
            onChanged: (value) {
              widget.onLocationChanged(value);
              setState(() {});
            },
            keyboardType: TextInputType.streetAddress,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            style: const TextStyle(color: AppColors.navy),
            decoration: InputDecoration(
              hintText: 'e.g. T5J 0N3 or 10123 99 Street',
              counterText: '',
              filled: true,
              fillColor: AppColors.white,
              prefixIcon: const Icon(Icons.place_outlined, color: AppColors.turquoise),
              errorText: invalid ? kInvalidLocationMessage : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadius),
                borderSide: const BorderSide(color: Color(0xFFE1E8EF)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
