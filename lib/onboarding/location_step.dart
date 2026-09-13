import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_colors.dart';
import '../app_styles.dart';
import '../widgets/pressable.dart';

class LocationStep extends StatefulWidget {
  const LocationStep({
    super.key,
    required this.lat,
    required this.lng,
    required this.onLocationChanged,
  });

  final double lat;
  final double lng;
  final ValueChanged<({double lat, double lng})> onLocationChanged;

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  late final _latController = TextEditingController(text: widget.lat.toString());
  late final _lngController = TextEditingController(text: widget.lng.toString());

  bool _isLocating = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _applyManualEntry() {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    if (lat == null || lng == null) return;
    widget.onLocationChanged((lat: lat, lng: lng));
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _statusMessage = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission was denied.';
      }

      final position = await Geolocator.getCurrentPosition();
      _latController.text = position.latitude.toString();
      _lngController.text = position.longitude.toString();
      widget.onLocationChanged((lat: position.latitude, lng: position.longitude));

      setState(() {
        _statusIsError = false;
        _statusMessage =
            'Location detected: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Could not get your location: $e';
      });
    } finally {
      setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Where are you located?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We'll use this to find providers near you.",
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        Pressable(
          enabled: !_isLocating,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isLocating ? null : _useCurrentLocation,
              icon: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: AppColors.turquoise),
              label: Text(
                _isLocating ? 'Detecting location…' : 'Use my current location',
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
            style: TextStyle(
              fontSize: 13,
              color: _statusIsError ? Colors.red.shade700 : AppColors.turquoise,
            ),
          ),
        ],
        const SizedBox(height: 32),
        Text(
          'OR ENTER MANUALLY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: AppColors.navy.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _CoordinateField(
                label: 'Latitude',
                controller: _latController,
                onChanged: (_) => _applyManualEntry(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _CoordinateField(
                label: 'Longitude',
                controller: _lngController,
                onChanged: (_) => _applyManualEntry(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      style: const TextStyle(color: AppColors.navy),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: Color(0xFFE1E8EF)),
        ),
      ),
    );
  }
}
