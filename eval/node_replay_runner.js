// node_replay_runner.js
// Replays trips through compiled TypeScript scoring engine logic (functions/lib/scoring.js)
// to verify parity with Python simulation within 5%.

const fs = require('fs');
const path = require('path');
const {
  scoreSlot,
  scoreAndRankSlots,
  evaluateInTransitUpgrade,
} = require('../functions/lib/scoring');

function buildFacility(config) {
  const facCfg = config.facility || {};
  const totalSlots = facCfg.total_slots || 72;
  const layout = facCfg.layout || {};
  const rowDistances = layout.row_distances_meters || {};
  const coveredCount = facCfg.covered_slots_count || 24;
  const slotSizes = facCfg.slot_sizes || { small: 42, medium: 22, large: 8 };

  const sizes = [
    ...new Array(slotSizes.small || 42).fill('small'),
    ...new Array(slotSizes.medium || 22).fill('medium'),
    ...new Array(slotSizes.large || 8).fill('large'),
  ];

  const slots = [];
  let slotIdx = 0;
  const rowNames = Object.keys(rowDistances).sort();

  for (const rName of rowNames) {
    const dists = rowDistances[rName];
    for (const d of dists) {
      if (slotIdx >= totalSlots) break;
      const sId = `slot-${rName.toLowerCase()}-${String(slotIdx + 1).padStart(2, '0')}`;
      const sType = slotIdx < coveredCount ? 'covered' : 'standard';
      const sSize = slotIdx < sizes.length ? sizes[slotIdx] : 'medium';

      slots.push({
        id: sId,
        row: rName,
        size: sSize,
        type: sType,
        walkingDistanceMeters: Number(d),
        state: 'available',
        currentBookingId: null,
      });
      slotIdx++;
    }
  }

  const lot = {
    id: facCfg.lot_id || 'lot-colombo-01',
    totalSlots: slots.length,
    freeSlots: slots.length,
  };

  return { slots, lot };
}

function runReplay(payloadPath) {
  const raw = fs.readFileSync(payloadPath, 'utf-8');
  const { trips, config } = JSON.parse(raw);
  const { slots, lot } = buildFacility(config);
  const slotMap = new Map(slots.map((s) => [s.id, s]));

  const holdDurationSec = (config.policies?.hold_duration_minutes || 15.0) * 60.0;
  const inTransitTriggerEta = config.policies?.in_transit_trigger_eta_minutes || 10.0;
  const kLogistic = config.acceptance_model?.k || 0.04;
  const d0Logistic = config.acceptance_model?.d0 || 25.0;

  const activeReservations = new Map();
  const completedBookings = [];
  let rejectedCount = 0;
  let autoReleasedCount = 0;
  let upgradesOffered = 0;
  let upgradesAccepted = 0;

  const events = [];
  for (const t of trips) {
    events.push({ timeSec: t.request_time_sec, type: 'REQUEST', data: t });
  }
  events.sort((a, b) => a.timeSec - b.timeSec);

  function syncLot() {
    let free = 0;
    for (const s of slots) {
      if (s.state === 'available') free++;
    }
    lot.freeSlots = free;
  }

  while (events.length > 0) {
    const ev = events.shift();
    const timeSec = ev.timeSec;
    syncLot();

    if (ev.type === 'REQUEST') {
      const trip = ev.data;
      const ranked = scoreAndRankSlots(
        slots,
        lot,
        trip.vehicle,
        trip.preferences
      );

      if (!ranked || ranked.length === 0) {
        rejectedCount++;
        continue;
      }

      const selected = ranked[0].slot;
      const sObj = slotMap.get(selected.id);
      sObj.state = 'reserved';
      sObj.currentBookingId = trip.trip_id;
      syncLot();

      const scheduledArr = trip.request_time_sec + trip.initial_eta_minutes * 60.0;
      const actualArr = scheduledArr + trip.delay_minutes * 60.0;
      const evalTime = Math.max(
        trip.request_time_sec,
        scheduledArr - inTransitTriggerEta * 60.0
      );
      const holdExpire = scheduledArr + holdDurationSec;

      const resRecord = {
        trip,
        slotId: sObj.id,
        status: 'reserved',
        scheduledArr,
        actualArr,
        holdExpire,
        departureSec: actualArr + trip.parking_duration_sec,
        distanceSavedM: 0.0,
      };
      activeReservations.set(trip.trip_id, resRecord);

      events.push({ timeSec: evalTime, type: 'IN_TRANSIT_EVAL', data: trip.trip_id });
      events.push({ timeSec: holdExpire, type: 'EXPIRE_HOLD', data: trip.trip_id });
      if (!trip.is_no_show) {
        events.push({ timeSec: actualArr, type: 'ACTUAL_ARRIVAL', data: trip.trip_id });
      }
      events.sort((a, b) => a.timeSec - b.timeSec);
    } else if (ev.type === 'IN_TRANSIT_EVAL') {
      const bId = ev.data;
      const res = activeReservations.get(bId);
      if (!res || res.status !== 'reserved') continue;

      const currentS = slotMap.get(res.slotId);
      const etaNowMin = Math.max(0.0, (res.scheduledArr - timeSec) / 60.0);

      const availableCand = slots.filter((s) => s.state === 'available');
      const upgradeRes = evaluateInTransitUpgrade(
        currentS,
        availableCand,
        lot,
        res.trip.vehicle,
        res.trip.preferences,
        etaNowMin
      );

      if (upgradeRes.isUpgradeOffered && upgradeRes.candidateSlotScore) {
        const bestSlot = upgradeRes.candidateSlotScore.slot;
        const distanceSavedM = upgradeRes.distanceSavedMeters;
        upgradesOffered++;
        // Exogenous logistic acceptance model
        const logitArg = -kLogistic * (distanceSavedM - d0Logistic);
        const pAccept = 1.0 / (1.0 + Math.exp(logitArg));
        const accepted = res.trip.acceptance_rand < pAccept;

        if (accepted) {
          upgradesAccepted++;
          currentS.state = 'available';
          currentS.currentBookingId = null;

          const targetS = slotMap.get(bestSlot.id);
          targetS.state = 'reserved';
          targetS.currentBookingId = bId;

          res.slotId = targetS.id;
          res.distanceSavedM = distanceSavedM;
          syncLot();
        }
      }
    } else if (ev.type === 'EXPIRE_HOLD') {
      const bId = ev.data;
      const res = activeReservations.get(bId);
      if (!res || res.status !== 'reserved') continue;

      res.status = 'auto_released';
      const sObj = slotMap.get(res.slotId);
      sObj.state = 'available';
      sObj.currentBookingId = null;
      autoReleasedCount++;
      syncLot();
    } else if (ev.type === 'ACTUAL_ARRIVAL') {
      const bId = ev.data;
      const res = activeReservations.get(bId);
      if (!res || res.status !== 'reserved') continue;

      res.status = 'occupied';
      const sObj = slotMap.get(res.slotId);
      sObj.state = 'occupied';
      syncLot();

      events.push({ timeSec: res.departureSec, type: 'DEPARTURE', data: bId });
      events.sort((a, b) => a.timeSec - b.timeSec);
    } else if (ev.type === 'DEPARTURE') {
      const bId = ev.data;
      const res = activeReservations.get(bId);
      if (!res) continue;

      res.status = 'completed';
      const sObj = slotMap.get(res.slotId);
      sObj.state = 'available';
      sObj.currentBookingId = null;
      syncLot();

      completedBookings.push(res);
      activeReservations.delete(bId);
    }
  }

  const nCompleted = completedBookings.length;
  const meanWalk =
    nCompleted > 0
      ? completedBookings.reduce((sum, b) => sum + slotMap.get(b.slotId).walkingDistanceMeters, 0) /
        nCompleted
      : 0.0;
  const walkSavedMean =
    nCompleted > 0
      ? completedBookings.reduce((sum, b) => sum + b.distanceSavedM, 0) / nCompleted
      : 0.0;

  const result = {
    total_trips: trips.length,
    completed_parkings: nCompleted,
    rejections: rejectedCount,
    rejection_rate_pct: Number(((rejectedCount / trips.length) * 100.0).toFixed(2)),
    mean_walking_distance_m: Number(meanWalk.toFixed(2)),
    walking_distance_saved_mean_m: Number(walkSavedMean.toFixed(2)),
    upgrades_offered: upgradesOffered,
    upgrades_accepted: upgradesAccepted,
  };

  console.log(JSON.stringify(result));
}

const payloadPath = process.argv[2];
runReplay(payloadPath);
