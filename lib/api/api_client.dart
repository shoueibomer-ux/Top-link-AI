import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'match_result.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

// The Android emulator can't reach the host machine via "localhost" — that
// resolves to the emulator itself. 10.0.2.2 is its alias for the host.
String _defaultBaseUrl() {
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  return 'http://$host:8000/api';
}

// Shared secret required by the backend (see matching.permissions.HasApiKey).
// Must match the backend's API_KEY. The default here is a dev-only value —
// a real deployment overrides it at build time with
// --dart-define=API_KEY=<the production key>, so the real secret never sits
// in source control.
const _apiKey = String.fromEnvironment('API_KEY', defaultValue: 'dev-local-shared-key');

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  final String baseUrl;

  // Demo location (Edmonton) used to prefill the location step.
  static const demoLat = 53.5444;
  static const demoLng = -113.4909;

  static const _headers = {
    'Content-Type': 'application/json',
    'X-API-Key': _apiKey,
  };

  Future<int> createAnonymousProfile({
    required String description,
    required double lat,
    required double lng,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/profiles/'),
      headers: _headers,
      body: jsonEncode({
        'name': 'App User',
        'role': 'individual',
        'description': description,
        'lat': lat,
        'lng': lng,
        // This profile represents a requester, not a service provider, so it
        // must never turn up as a candidate in someone else's match results.
        'available': false,
      }),
    );

    if (response.statusCode != 201) {
      throw ApiException('Could not create profile (${response.statusCode}).');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as int;
  }

  Future<List<MatchResult>> requestMatch({
    required int requesterId,
    required String requestText,
    required double lat,
    required double lng,
    double maxDistanceKm = 25,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/match/'),
      headers: _headers,
      body: jsonEncode({
        'requester': requesterId,
        'request_text': requestText,
        'lat': lat,
        'lng': lng,
        'max_distance_km': maxDistanceKm,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException('Matching failed (${response.statusCode}).');
    }
    final results = jsonDecode(response.body) as List<dynamic>;
    return results
        .map((r) => MatchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
