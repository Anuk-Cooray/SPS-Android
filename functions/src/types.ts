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
  updatedAt: string;
  updatedBy: 'app' | 'cctv' | 'admin' | 'function' | 'system';
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
  qrToken: string;
  checkedInAt?: string | null;
  completedAt?: string | null;
  holdExpiresAt: string;
  extensionsCount: number;
  slotSwapHistory?: Array<{
    previousSlotId: string;
    newSlotId: string;
    timestamp: string;
    distanceSavedMeters: number;
    scoreImprovementPercent: number;
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
  | 'auto_released';

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
}

export interface CancelBookingRequest {
  bookingId: string;
}

export interface CheckInRequest {
  bookingId?: string;
  qrToken: string;
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
