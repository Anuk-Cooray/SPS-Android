import '../models/billing/demand_forecast_point.dart';
import '../models/billing/fee_quote.dart';
import '../models/billing/invoice.dart';
import '../models/billing/payment_session.dart';
import '../../core/theme/app_theme.dart';
import '../models/booking_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/vehicle_model.dart';

/// Contract for Component: CCTV Occupancy Detection (Assigned to: Samudi)
abstract interface class LotOccupancyService {
  /// Fetches real-time slot occupancy from CCTV streams
  Future<List<ParkingSlot>> fetchLotSlots(String lotId);

  /// Stream of occupancy updates pushed by CCTV vision backend
  Stream<Map<String, SlotState>> get liveOccupancyStream;
}

/// Contract for Component: QR Barrier & Find My Car (Assigned to: Varunprasath)
abstract interface class BarrierService {
  /// Validates QR token at entry/exit barrier and unlocks gate
  Future<bool> verifyAndOpenBarrier({
    required String bookingId,
    required String qrToken,
  });

  /// Returns GPS coordinates & turn-by-turn walking steps to parked vehicle
  Future<Map<String, dynamic>> getWalkingDirectionsToCar({
    required String slotId,
    required double userLat,
    required double userLng,
  });
}

/// Contract for Component: Smart Billing & QR Payment (Assigned to: Rathnayake)
abstract interface class BillingService {
  /// Calculates final fee with base duration, extension charges, and upgrade offsets
  Future<int> calculateFee({
    required String bookingId,
    required int parkedMinutes,
    required int extensionFee,
  });

  /// Processes digital in-app payment or attendant invoice
  Future<bool> processPayment({
    required String bookingId,
    required int amount,
    required String paymentMethod,
  });

  Future<FeeQuote> quoteFee({
    required String bookingId,
    required DateTime entryTime,
    required DateTime exitTime,
    required String lotId,
    int extensionMinutes = 0,
    int arrivalExtensionFee = 0,
    String? upgradeFromSlotId,
    String? upgradeToSlotId,
  });
  Future<Invoice> createInvoice({
    required String bookingId,
    required FeeQuote quote,
  });
  Future<PaymentSession> startPayment({
    required String invoiceId,
    required String method,
  });
  Future<Invoice> getInvoice(String invoiceId);
  Future<List<DemandForecastPoint>> getDemandForecast({
    required String lotId,
    int horizonHours = 24,
  });
}

/// Contract for Component: Dynamic Slot Re-optimization & Reservation (Assigned to: Anuk - Team Lead)
abstract interface class ReoptimizationService {
  /// Scores all free slots in a lot using weighted multi-criteria model (SYS-01)
  ParkingSlot? scoreAndRecommendBestSlot({
    required ParkingLot lot,
    required Vehicle vehicle,
    required bool preferNearEntrance,
  });

  /// Evaluates whether a significantly closer/better slot is available when ETA = 10 min (SYS-03)
  ParkingSlot? checkCandidateUpgrade({
    required ParkingLot lot,
    required ParkingSlot currentSlot,
    required Vehicle vehicle,
  });

  /// Holds the upgraded slot atomically for 60 seconds (SYS-04)
  Future<bool> holdUpgradeSlot({
    required String bookingId,
    required String newSlotId,
  });

  /// Finalizes the slot swap upon driver acceptance
  Future<Booking> executeSlotSwap({
    required Booking currentBooking,
    required ParkingSlot newSlot,
  });
}
