// google_maps_launcher.dart
// Native Google Maps Intent and Turn-by-Turn Navigation Launcher

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleMapsLauncher {
  /// Launches the official Google Maps app on the device to start turn-by-turn navigation.
  /// Falls back to Google Maps directions web URL if the native app is not installed.
  static Future<bool> launchNavigation({
    required double destinationLat,
    required double destinationLng,
    double? originLat,
    double? originLng,
    String? destinationLabel,
  }) async {
    // 1. Android Google Navigation Intent (Direct turn-by-turn driving mode)
    final navIntentUri = Uri.parse(
      'google.navigation:q=$destinationLat,$destinationLng&mode=d',
    );

    try {
      if (await canLaunchUrl(navIntentUri)) {
        final launched = await launchUrl(
          navIntentUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }
    } catch (e) {
      debugPrint('[GoogleMapsLauncher] Google Navigation intent failed: $e');
    }

    // 2. Standard Google Maps Directions URL (Supports origin + destination)
    final originParam = (originLat != null && originLng != null)
        ? '&origin=$originLat,$originLng'
        : '';
    final webUrlString =
        'https://www.google.com/maps/dir/?api=1$originParam&destination=$destinationLat,$destinationLng&travelmode=driving';
    final webUri = Uri.parse(webUrlString);

    try {
      if (await canLaunchUrl(webUri)) {
        return await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('[GoogleMapsLauncher] Web Google Maps directions URL failed: $e');
    }

    // 3. Fallback Geo URI
    final geoUri = Uri.parse(
      'geo:$destinationLat,$destinationLng?q=$destinationLat,$destinationLng(${Uri.encodeComponent(destinationLabel ?? "Parking Lot")})',
    );

    try {
      if (await canLaunchUrl(geoUri)) {
        return await launchUrl(
          geoUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      debugPrint('[GoogleMapsLauncher] Geo URI fallback failed: $e');
    }

    return false;
  }

  /// Opens a pin location in Google Maps without starting navigation
  static Future<bool> openLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[GoogleMapsLauncher] Failed to open Google Maps location: $e');
      return false;
    }
  }
}
