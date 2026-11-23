// colombo_navigation_test.dart
// Unit tests for Colombo Landmarks, Uber-Style Navigation, and Google Maps Launching

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/data/services/colombo_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Colombo Public & Famous Landmarks Registry (SYS-01 / SYS-03)', () {
    test('Registry contains essential crowded and famous Colombo hubs', () {
      final landmarks = ColomboLocationService.landmarks;
      expect(landmarks.length, greaterThanOrEqualTo(10));

      final names = landmarks.map((l) => l.name).toList();
      expect(names.any((n) => n.contains('One Galle Face')), isTrue);
      expect(names.any((n) => n.contains('Pettah')), isTrue);
      expect(names.any((n) => n.contains('Lotus Tower')), isTrue);
      expect(names.any((n) => n.contains('Majestic City')), isTrue);
      expect(names.any((n) => n.contains('SLIIT')), isTrue);
    });

    test('search filters landmarks accurately by name, category, or address', () {
      final galleResults = ColomboLocationService.search('Galle');
      expect(galleResults.isNotEmpty, isTrue);
      expect(galleResults.any((l) => l.id == 'one-galle-face'), isTrue);
      expect(galleResults.any((l) => l.id == 'galle-face-green'), isTrue);

      final hospitalResults = ColomboLocationService.search('Hospital');
      expect(hospitalResults.isNotEmpty, isTrue);
      expect(hospitalResults.first.id, equals('nhsl-hospital'));

      final mallResults = ColomboLocationService.search('Shopping & Mall');
      expect(mallResults.length, greaterThanOrEqualTo(3));
    });

    test('getCrowdedPlaces returns only locations marked as crowded with congestion metrics', () {
      final crowded = ColomboLocationService.getCrowdedPlaces();
      expect(crowded.isNotEmpty, isTrue);
      for (final place in crowded) {
        expect(place.isCrowded, isTrue);
        expect(place.congestionMultiplier, greaterThanOrEqualTo(1.1));
      }
    });

    test('distanceToKm and estimatedDriveMinutes calculate accurate Colombo urban telemetry', () {
      final sliit = ColomboLocationService.getLandmarkById('sliit-malabe');
      final ogf = ColomboLocationService.getLandmarkById('one-galle-face');

      // Driving distance from Malabe to Galle Face ~ 12-18 km
      final distKm = ogf.distanceToKm(sliit.latitude, sliit.longitude);
      expect(distKm, inInclusiveRange(10.0, 22.0));

      // Drive minutes in Colombo traffic
      final driveMins = ogf.estimatedDriveMinutes(sliit.latitude, sliit.longitude);
      expect(driveMins, inInclusiveRange(30, 90));
    });

    test('Each Colombo landmark provides adjacent Smart Parking facilities with slots', () {
      for (final landmark in ColomboLocationService.landmarks) {
        expect(landmark.nearbyLots.isNotEmpty, isTrue);
        final primary = landmark.nearbyLots.first;
        expect(primary.hourlyRate, greaterThan(0));
        expect(primary.totalSlots, greaterThan(0));
      }
    });
  });
}
