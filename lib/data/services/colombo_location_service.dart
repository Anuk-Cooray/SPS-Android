// colombo_location_service.dart
// Colombo Public & Famous Landmark Registry and Location Routing Service

import '../../core/theme/app_theme.dart';
import '../models/colombo_landmark_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/vehicle_model.dart';

class ColomboLocationService {
  // Pre-configured default Colombo landmarks
  static final List<ColomboLandmark> _landmarks = [
    ColomboLandmark(
      id: 'sliit-malabe',
      name: 'SLIIT Malabe Campus',
      address: 'New Kandy Rd, Malabe',
      zone: 'Greater Colombo',
      category: 'University & Tech',
      congestionLevel: 'Moderate',
      congestionMultiplier: 1.10,
      latitude: 6.9147,
      longitude: 79.9729,
      popularHours: '8:00 AM - 5:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-main',
      primaryLotName: 'Main Building Lot',
      nearbyLots: [
        const ParkingLot(
          id: 'lot-main',
          name: 'Main Building Lot',
          campusZone: 'SLIIT Malabe Campus',
          latitude: 6.9147,
          longitude: 79.9729,
          distanceMeters: 80,
          hourlyRate: 100,
          totalSlots: 24,
          freeSlots: 12,
        ),
        const ParkingLot(
          id: 'lot-new-p2',
          name: 'New Building P2',
          campusZone: 'SLIIT Malabe Campus',
          latitude: 6.9135,
          longitude: 79.9715,
          distanceMeters: 240,
          hourlyRate: 80,
          totalSlots: 24,
          freeSlots: 4,
        ),
        const ParkingLot(
          id: 'lot-sports',
          name: 'Sports Complex',
          campusZone: 'SLIIT Malabe Campus',
          latitude: 6.9160,
          longitude: 79.9745,
          distanceMeters: 450,
          hourlyRate: 50,
          totalSlots: 18,
          freeSlots: 0,
        ),
      ],
    ),
    ColomboLandmark(
      id: 'one-galle-face',
      name: 'One Galle Face Mall & Shangri-La',
      address: '1A Centre Rd, Galle Face, Colombo 02',
      zone: 'Colombo 02',
      category: 'Shopping & Mall',
      congestionLevel: 'Very High',
      congestionMultiplier: 1.45,
      latitude: 6.9298,
      longitude: 79.8459,
      popularHours: '10:00 AM - 10:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-ogf-b1',
      primaryLotName: 'OGF Multi-Level Basement',
      nearbyLots: [
        ParkingLot(
          id: 'lot-ogf-b1',
          name: 'OGF Multi-Level Basement',
          campusZone: 'Galle Face Commercial Hub',
          latitude: 6.9298,
          longitude: 79.8459,
          distanceMeters: 30,
          hourlyRate: 150,
          totalSlots: 30,
          freeSlots: 14,
          slots: _generateGenericSlots('lot-ogf-b1', 14),
        ),
        ParkingLot(
          id: 'lot-shangrila-p',
          name: 'Shangri-La Plaza Parking',
          campusZone: 'Galle Face Commercial Hub',
          latitude: 6.9305,
          longitude: 79.8450,
          distanceMeters: 180,
          hourlyRate: 200,
          totalSlots: 20,
          freeSlots: 6,
          slots: _generateGenericSlots('lot-shangrila-p', 6),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'galle-face-green',
      name: 'Galle Face Green & Promenade',
      address: 'Galle Main Rd, Colombo 03',
      zone: 'Colombo 03',
      category: 'Promenade & Oceanfront',
      congestionLevel: 'High',
      congestionMultiplier: 1.35,
      latitude: 6.9271,
      longitude: 79.8436,
      popularHours: '4:00 PM - 9:30 PM',
      isCrowded: true,
      primaryLotId: 'lot-gfg-seafront',
      primaryLotName: 'Galle Face Seafront Lot',
      nearbyLots: [
        ParkingLot(
          id: 'lot-gfg-seafront',
          name: 'Galle Face Seafront Lot',
          campusZone: 'Marine Drive Zone',
          latitude: 6.9271,
          longitude: 79.8436,
          distanceMeters: 60,
          hourlyRate: 120,
          totalSlots: 25,
          freeSlots: 9,
          slots: _generateGenericSlots('lot-gfg-seafront', 9),
        ),
        ParkingLot(
          id: 'lot-kollupitiya-edge',
          name: 'Kollupitiya Junction Bay',
          campusZone: 'Marine Drive Zone',
          latitude: 6.9215,
          longitude: 79.8470,
          distanceMeters: 310,
          hourlyRate: 100,
          totalSlots: 20,
          freeSlots: 5,
          slots: _generateGenericSlots('lot-kollupitiya-edge', 5),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'colombo-fort-pettah',
      name: 'Colombo Fort Station & Pettah Market',
      address: 'Olcott Mawatha, Pettah, Colombo 11',
      zone: 'Colombo 11',
      category: 'Transit & Market',
      congestionLevel: 'Extreme',
      congestionMultiplier: 1.60,
      latitude: 6.9344,
      longitude: 79.8504,
      popularHours: '7:00 AM - 8:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-fort-railway',
      primaryLotName: 'Fort Station Central Car Park',
      nearbyLots: [
        ParkingLot(
          id: 'lot-fort-railway',
          name: 'Fort Station Central Car Park',
          campusZone: 'Pettah Commercial Zone',
          latitude: 6.9344,
          longitude: 79.8504,
          distanceMeters: 50,
          hourlyRate: 100,
          totalSlots: 28,
          freeSlots: 7,
          slots: _generateGenericSlots('lot-fort-railway', 7),
        ),
        ParkingLot(
          id: 'lot-olcott-mw',
          name: 'Olcott Multi-Level Terminal',
          campusZone: 'Pettah Commercial Zone',
          latitude: 6.9352,
          longitude: 79.8520,
          distanceMeters: 220,
          hourlyRate: 120,
          totalSlots: 32,
          freeSlots: 11,
          slots: _generateGenericSlots('lot-olcott-mw', 11),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'lotus-tower',
      name: 'Colombo Lotus Tower (Nelum Kuluna)',
      address: 'AC6, Maradana, Colombo 10',
      zone: 'Colombo 10',
      category: 'Tourism & Landmark',
      congestionLevel: 'High',
      congestionMultiplier: 1.30,
      latitude: 6.9272,
      longitude: 79.8584,
      popularHours: '2:00 PM - 10:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-lotus-visitor',
      primaryLotName: 'Lotus Tower Visitor Parking',
      nearbyLots: [
        ParkingLot(
          id: 'lot-lotus-visitor',
          name: 'Lotus Tower Visitor Parking',
          campusZone: 'Lake Leisure Zone',
          latitude: 6.9272,
          longitude: 79.8584,
          distanceMeters: 40,
          hourlyRate: 150,
          totalSlots: 35,
          freeSlots: 18,
          slots: _generateGenericSlots('lot-lotus-visitor', 18),
        ),
        ParkingLot(
          id: 'lot-beira-lakeview',
          name: 'Beira Lake East Lot',
          campusZone: 'Lake Leisure Zone',
          latitude: 6.9260,
          longitude: 79.8570,
          distanceMeters: 260,
          hourlyRate: 80,
          totalSlots: 18,
          freeSlots: 8,
          slots: _generateGenericSlots('lot-beira-lakeview', 8),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'majestic-city',
      name: 'Majestic City & Unity Plaza',
      address: 'Galle Rd, Bambalapitiya, Colombo 04',
      zone: 'Colombo 04',
      category: 'Shopping & Mall',
      congestionLevel: 'Very High',
      congestionMultiplier: 1.40,
      latitude: 6.8942,
      longitude: 79.8553,
      popularHours: '10:00 AM - 8:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-mc-basement',
      primaryLotName: 'MC Underground Parking',
      nearbyLots: [
        ParkingLot(
          id: 'lot-mc-basement',
          name: 'MC Underground Parking',
          campusZone: 'Bambalapitiya Shopping Hub',
          latitude: 6.8942,
          longitude: 79.8553,
          distanceMeters: 25,
          hourlyRate: 100,
          totalSlots: 26,
          freeSlots: 8,
          slots: _generateGenericSlots('lot-mc-basement', 8),
        ),
        ParkingLot(
          id: 'lot-unity-plaza',
          name: 'Unity Plaza Multi-Story',
          campusZone: 'Bambalapitiya Shopping Hub',
          latitude: 6.8950,
          longitude: 79.8558,
          distanceMeters: 140,
          hourlyRate: 120,
          totalSlots: 20,
          freeSlots: 4,
          slots: _generateGenericSlots('lot-unity-plaza', 4),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'havelock-city',
      name: 'Havelock City Mall',
      address: '324 Havelock Rd, Colombo 05',
      zone: 'Colombo 05',
      category: 'Shopping & Mall',
      congestionLevel: 'High',
      congestionMultiplier: 1.25,
      latitude: 6.8837,
      longitude: 79.8665,
      popularHours: '11:00 AM - 9:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-havelock-p1',
      primaryLotName: 'Havelock City Basement P1',
      nearbyLots: [
        ParkingLot(
          id: 'lot-havelock-p1',
          name: 'Havelock City Basement P1',
          campusZone: 'Havelock Commercial Zone',
          latitude: 6.8837,
          longitude: 79.8665,
          distanceMeters: 30,
          hourlyRate: 150,
          totalSlots: 40,
          freeSlots: 22,
          slots: _generateGenericSlots('lot-havelock-p1', 22),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'town-hall-viharamahadevi',
      name: 'Town Hall & Viharamahadevi Park',
      address: 'F. R. Senanayake Mawatha, Colombo 07',
      zone: 'Colombo 07',
      category: 'Civic & Leisure',
      congestionLevel: 'Moderate',
      congestionMultiplier: 1.15,
      latitude: 6.9147,
      longitude: 79.8653,
      popularHours: '6:00 AM - 8:00 PM',
      isCrowded: false,
      primaryLotId: 'lot-town-hall',
      primaryLotName: 'Town Hall Public Lot',
      nearbyLots: [
        ParkingLot(
          id: 'lot-town-hall',
          name: 'Town Hall Public Lot',
          campusZone: 'Cinnamon Gardens Zone',
          latitude: 6.9147,
          longitude: 79.8653,
          distanceMeters: 70,
          hourlyRate: 60,
          totalSlots: 20,
          freeSlots: 10,
          slots: _generateGenericSlots('lot-town-hall', 10),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'nhsl-hospital',
      name: 'National Hospital of Sri Lanka (NHSL)',
      address: 'Regent St, Colombo 10',
      zone: 'Colombo 10',
      category: 'Healthcare & Emergency',
      congestionLevel: 'Very High',
      congestionMultiplier: 1.50,
      latitude: 6.9192,
      longitude: 79.8687,
      popularHours: '24 Hours Emergency',
      isCrowded: true,
      primaryLotId: 'lot-nhsl-emergency',
      primaryLotName: 'NHSL Emergency Parking Bay',
      nearbyLots: [
        ParkingLot(
          id: 'lot-nhsl-emergency',
          name: 'NHSL Emergency Parking Bay',
          campusZone: 'Medical District',
          latitude: 6.9192,
          longitude: 79.8687,
          distanceMeters: 40,
          hourlyRate: 50,
          totalSlots: 24,
          freeSlots: 6,
          slots: _generateGenericSlots('lot-nhsl-emergency', 6),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'independence-square',
      name: 'Independence Memorial Hall & Arcade',
      address: 'Independence Ave, Colombo 07',
      zone: 'Colombo 07',
      category: 'Civic & Leisure',
      congestionLevel: 'Moderate',
      congestionMultiplier: 1.15,
      latitude: 6.9044,
      longitude: 79.8675,
      popularHours: '5:30 AM - 9:00 PM',
      isCrowded: false,
      primaryLotId: 'lot-arcade-colombo',
      primaryLotName: 'Arcade Independence Parking',
      nearbyLots: [
        ParkingLot(
          id: 'lot-arcade-colombo',
          name: 'Arcade Independence Parking',
          campusZone: 'Cinnamon Gardens Zone',
          latitude: 6.9044,
          longitude: 79.8675,
          distanceMeters: 50,
          hourlyRate: 80,
          totalSlots: 25,
          freeSlots: 15,
          slots: _generateGenericSlots('lot-arcade-colombo', 15),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'bmich',
      name: 'BMICH Convention Centre',
      address: 'Bauddhaloka Mawatha, Colombo 07',
      zone: 'Colombo 07',
      category: 'Conventions & Events',
      congestionLevel: 'High',
      congestionMultiplier: 1.30,
      latitude: 6.9015,
      longitude: 79.8735,
      popularHours: '9:00 AM - 10:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-bmich-p1',
      primaryLotName: 'BMICH Gate 1 Main Lot',
      nearbyLots: [
        ParkingLot(
          id: 'lot-bmich-p1',
          name: 'BMICH Gate 1 Main Lot',
          campusZone: 'Exhibition District',
          latitude: 6.9015,
          longitude: 79.8735,
          distanceMeters: 80,
          hourlyRate: 100,
          totalSlots: 50,
          freeSlots: 28,
          slots: _generateGenericSlots('lot-bmich-p1', 28),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'colombo-city-centre',
      name: 'Colombo City Centre (CCC)',
      address: '137 Sir James Pieris Mawatha, Colombo 02',
      zone: 'Colombo 02',
      category: 'Shopping & Mall',
      congestionLevel: 'Very High',
      congestionMultiplier: 1.40,
      latitude: 6.9175,
      longitude: 79.8540,
      popularHours: '10:00 AM - 10:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-ccc-mall',
      primaryLotName: 'CCC Podium Car Park',
      nearbyLots: [
        ParkingLot(
          id: 'lot-ccc-mall',
          name: 'CCC Podium Car Park',
          campusZone: 'Slave Island Commercial Zone',
          latitude: 6.9175,
          longitude: 79.8540,
          distanceMeters: 30,
          hourlyRate: 150,
          totalSlots: 30,
          freeSlots: 12,
          slots: _generateGenericSlots('lot-ccc-mall', 12),
        ),
      ],
    ),
    ColomboLandmark(
      id: 'diyatha-uyana',
      name: 'Diyatha Uyana & Water\'s Edge',
      address: 'Kaduwela Rd, Battaramulla',
      zone: 'Greater Colombo',
      category: 'Civic & Leisure',
      congestionLevel: 'High',
      congestionMultiplier: 1.25,
      latitude: 6.9022,
      longitude: 79.9142,
      popularHours: '3:00 PM - 10:00 PM',
      isCrowded: true,
      primaryLotId: 'lot-diyatha-park',
      primaryLotName: 'Diyatha Waterfront Parking',
      nearbyLots: [
        ParkingLot(
          id: 'lot-diyatha-park',
          name: 'Diyatha Waterfront Parking',
          campusZone: 'Battaramulla Lake Zone',
          latitude: 6.9022,
          longitude: 79.9142,
          distanceMeters: 45,
          hourlyRate: 70,
          totalSlots: 25,
          freeSlots: 11,
          slots: _generateGenericSlots('lot-diyatha-park', 11),
        ),
      ],
    ),
  ];

  /// Get all Colombo landmarks
  static List<ColomboLandmark> get landmarks => List.unmodifiable(_landmarks);

  /// Find a landmark by ID, falling back to SLIIT Malabe Campus
  static ColomboLandmark getLandmarkById(String id) {
    return _landmarks.firstWhere(
      (l) => l.id == id,
      orElse: () => _landmarks.first,
    );
  }

  /// Search landmarks by query string (name, address, zone, category)
  static List<ColomboLandmark> search(String query) {
    if (query.trim().isEmpty) return _landmarks;
    final q = query.trim().toLowerCase();
    return _landmarks.where((l) {
      return l.name.toLowerCase().contains(q) ||
          l.address.toLowerCase().contains(q) ||
          l.zone.toLowerCase().contains(q) ||
          l.category.toLowerCase().contains(q);
    }).toList();
  }

  /// Returns popular & crowded landmarks in Colombo
  static List<ColomboLandmark> getCrowdedPlaces() {
    return _landmarks.where((l) => l.isCrowded).toList();
  }

  /// Helper to generate generic realistic slots for dynamically discovered lots
  static List<ParkingSlot> _generateGenericSlots(String lotId, int freeCount) {
    final slots = <ParkingSlot>[];
    int remainingFree = freeCount;
    const rows = ['A', 'B', 'C', 'D'];
    int idCounter = 1;

    for (final row in rows) {
      for (int num = 1; num <= 6; num++) {
        final isFree = remainingFree > 0 && (idCounter % 2 == 0 || remainingFree >= 12);
        if (isFree) remainingFree--;

        slots.add(
          ParkingSlot(
            id: '$row-0$num',
            lotId: lotId,
            row: row,
            number: num,
            state: isFree ? SlotState.free : SlotState.taken,
            size: num > 4 ? VehicleSize.large : VehicleSize.medium,
            walkingDistanceMeters: (row.codeUnitAt(0) - 65) * 40 + (num * 15) + 30,
          ),
        );
        idCounter++;
      }
    }
    return slots;
  }
}
