// functions/test/feasibility.test.ts
// Smart Parking (J26-IT-335) — Learned ETA Model & Feasibility Unit Tests

import { expect } from 'chai';
import { evaluateArrivalFeasibility } from '../src/feasibility';

describe('Learned Sri Lankan ETA Correction & Feasibility Engine', () => {
  const malabeOrigin = { lat: 6.9040, lng: 79.9540 }; // Malabe junction
  const sliitCampus = { lat: 6.9147, lng: 79.9733 }; // SLIIT Campus Lot

  it('serves learned model with modelVersion v1.0.0-linear and positive correction factor', () => {
    // 8:30 AM on a Monday (Peak morning rush)
    const arrivalTime = new Date('2026-10-20T08:30:00.000Z');

    const result = evaluateArrivalFeasibility({
      originLat: malabeOrigin.lat,
      originLng: malabeOrigin.lng,
      destLat: sliitCampus.lat,
      destLng: sliitCampus.lng,
      requestedArrivalTime: arrivalTime,
      originZone: 'Malabe_Kaduwela',
      weatherFlag: 1, // Monsoon downpour
    });

    expect(result.modelVersion).to.equal('v1.0.0-linear');
    expect(result.drivingDistanceKm).to.be.greaterThan(2.0);
    expect(result.residualCorrectionFactor).to.be.greaterThan(1.0); // Traffic + rain causes delay
    expect(result.predictedEtaMinCorrected).to.be.greaterThan(result.predictedEtaMinProvider);
    expect(result.drivingDurationMinutes).to.equal(result.predictedEtaMinCorrected);
  });

  it('corrects ETA down during off-peak and weekend conditions', () => {
    // Sunday 11:00 AM (off-peak weekend)
    const weekendArrival = new Date('2026-10-25T11:00:00.000Z');

    const result = evaluateArrivalFeasibility({
      originLat: malabeOrigin.lat,
      originLng: malabeOrigin.lng,
      destLat: sliitCampus.lat,
      destLng: sliitCampus.lng,
      requestedArrivalTime: weekendArrival,
      weatherFlag: 0,
      holidayFlag: 0,
    });

    expect(result.modelVersion).to.equal('v1.0.0-linear');
    expect(result.predictedEtaMinCorrected).to.be.greaterThanOrEqual(3);
  });
});
