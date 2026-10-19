// types.ts
// Smart Parking (J26-IT-335) — Server Reservation Authority Data Types & Interfaces

export type VehicleSize = 'small' | 'medium' | 'large';
export type SlotType = 'normal' | 'disabled' | 'ev' | 'covered';
export type SlotState = 'available' | 'reserved' | 'held' | 'occupied' | 'blocked';

export type BookingStatus =
  | 'reserved'
  | 'upgraded'
  | 'held'
  | 'checkedIn'
  | 'extended'
  | 'completed'
  | 'cancelled'
  | 'auto_released';

export interface ParkingSlotDocument {
  id: string;
  lotId: string;
  row: string;
  number: number;
  size: VehicleSize;
  type: SlotType;
  walkingDistanceMeters: number;
  state: SlotState;
  bookingId: string | null;
  conflictFlag?: boolean;
  pendingCctvState?: SlotState | null;
  pendingCctvSince?: string | null;
  lastCctvAt?: string | null;
  updatedAt: string;
  updatedBy: 'app' | 'cctv' | 'admin' | 'function' | 'system' | 'payment';
}

export interface ParkingLotDocument {
  id: string;
  name: string;
  campusZone?: string;
  latitude: number;
  longitude: number;
  distanceMeters?: number;
  hourlyRate: number;
  totalSlots: number;
  freeSlots: number;
  openingHours?: string;
  updatedAt?: string;
}

export interface BookingChargeDocument {
  id: string;
  type: 'parking' | 'extension' | 'upgrade';
  amount: number;
  currency: 'LKR';
  timestamp: string;
  description: string;
}

export interface BookingDocument {
  id: string;
  userId: string;
  vehicleId: string;
  vehiclePlate: string;
  vehicleSize: VehicleSize;
  lotId: string;
  lotName: string;
  slotId: string;
  originalSlotId?: string | null;
  distanceSavedMeters?: number;
  bookedAt: string;
  arrivalTime: string;
  durationHours: number;
  status: BookingStatus;
  estimatedFee: number;
  extensionFee: number;
  finalFee: number;
  charges?: BookingChargeDocument[];
  reallocatedDueToConflict?: boolean;
  reallocatedFromSlotId?: string;
  qrToken: string;
  checkedInAt?: string | null;
  completedAt?: string | null;
  holdExpiresAt: string;
  extensionsCount: number;
  predictedEtaMinBaseline?: number;
  predictedEtaMinProvider?: number;
  predictedEtaMinCorrected?: number;
  modelVersion?: string;
  slotSwapHistory?: Array<{
    previousSlotId: string;
    newSlotId: string;
    timestamp: string;
    distanceSavedMeters: number;
    scoreImprovementPoints?: number;
    scoreImprovementPercent?: number;
  }>;
}

export type ParkingEventType =
  | 'booking_created'
  | 'booking_cancelled'
  | 'slot_upgraded'
  | 'hold_started'
  | 'hold_extended'
  | 'checked_in'
  | 'completed'
  | 'auto_released'
  | 'trip_telemetry_logged'
  | 'slot_conflict'
  | 'reallocated_due_to_conflict'
  | 'vacated_without_payment';

export interface ParkingEventDocument {
  id: string;
  bookingId: string;
  userId: string;
  lotId: string;
  slotId: string;
  eventType: ParkingEventType;
  timestamp: string;
  metadata?: Record<string, any>;
  description?: string;
}

export interface AdminAlertDocument {
  id: string;
  lotId: string;
  slotId: string;
  bookingId?: string;
  type: 'slot_conflict' | 'vacated_without_payment' | 'unauthorized_parking';
  severity: 'warning' | 'critical' | 'info';
  timestamp: string;
  description: string;
  resolved: boolean;
  metadata?: Record<string, any>;
}

export interface DeviceDocument {
  id: string;
  name: string;
  type: 'camera' | 'barrier' | 'payment_gateway';
  lotId: string;
  slotId?: string | null;
  apiKeyHash: string; // SHA-256
  isActive: boolean;
  lastSeenAt?: string;
}

export interface ProcessedPaymentDocument {
  paymentRef: string;
  bookingId: string;
  amountPaid: number;
  paymentMethod: string;
  processedAt: string;
  receiptNo: string;
}

export interface TripTelemetryDocument {
  id: string;
  tripId?: string;
  bookingId: string;
  userId: string;
  lotId: string;
  predictedEtaMinBaseline: number;
  predictedEtaMinProvider: number;
  predictedEtaMinCorrected: number;
  actualTravelMin: number;
  departureTime: string;
  arrivalTime: string;
  dayOfWeek: number;
  hour: number;
  distanceKm: number;
  originZone: string;
  weatherFlag: number;
  holidayFlag: number;
  modelVersion: string;
  loggedAt: string;
}

// Request and Response Interfaces

export interface CreateBookingRequest {
  lotId: string;
  slotId: string;
  vehicleId?: string;
  vehiclePlate: string;
  vehicleSize: VehicleSize;
  vehicleType?: string;
  arrivalTime: string; // ISO string
  durationHours: number;
  driverOrigin?: {
    latitude: number;
    longitude: number;
  };
  originZone?: string;
  weatherFlag?: number;
  holidayFlag?: number;
  providerEtaMinutes?: number;
}

export interface CancelBookingRequest {
  bookingId: string;
}

export interface CheckInRequest {
  bookingId?: string;
  qrToken: string;
  actualTravelMin?: number;
}

export interface ExtendHoldRequest {
  bookingId: string;
  minutes?: number;
}

export interface AcceptUpgradeRequest {
  bookingId: string;
  newSlotId: string;
  currentEtaMinutes?: number;
}

export interface IngestOccupancyRequest {
  lotId: string;
  slotId: string;
  occupied: boolean;
  confidence: number;
  timestamp: string;
  violation?: boolean;
}

export interface IngestOccupancyResponse {
  success: boolean;
  slotId: string;
  state: SlotState;
  conflictDetected: boolean;
  reallocated?: boolean;
  reallocatedToSlotId?: string;
  alertId?: string;
  message?: string;
  debounceStatus?: 'applied' | 'pending';
  timestamp: string;
}

export interface ValidateQrRequest {
  qrToken: string;
  barrierId: string;
  actualTravelMin?: number;
}

export interface ValidateQrResponse {
  allow: boolean;
  code?: 'OK' | 'WRONG_SLOT' | 'INVALID_SIGNATURE' | 'EXPIRED_OR_PREMATURE' | 'TOKEN_ALREADY_USED' | 'BOOKING_INACTIVE' | 'BOOKING_NOT_FOUND';
  bookingId?: string;
  lotId?: string;
  slotId?: string;
  driverName?: string;
  vehiclePlate?: string;
  reason?: string;
  message?: string;
}

export interface PaymentCompletedRequest {
  bookingId: string;
  paymentRef: string;
  amountPaid: number;
  paymentMethod: string;
  timestamp: string;
}

export interface PaymentCompletedResponse {
  success: boolean;
  bookingId: string;
  paymentRef: string;
  totalCharged: number;
  amountPaid: number;
  status: 'completed';
  slotFreed: string;
  receiptNo: string;
  isIdempotentReplay?: boolean;
}
