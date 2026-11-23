"""generate_synthetic_trips.py
Smart Parking Re-optimization System (J26-IT-335)
Synthetic Sri Lankan Urban Trip Dataset Generator

NOTICE:
This dataset is SYNTHETIC and generated exclusively for training and verifying
the ETA correction model pipeline until live vehicle telemetry is accumulated.
Simulates realistic Colombo arterial traffic dynamics including:
  - Peak morning (07:30-09:30) and evening (16:30-19:30) congestion on New Kandy Rd & Galle Rd
  - Tropical rain / monsoon precipitation slowdowns (15-35% delay)
  - Poya day & national public holiday flow variations
  - Sri Lankan corridor bottlenecks (Malabe, Kelaniya, Kollupitiya, Fort)
"""

import os
import csv
import json
import math
import random
from datetime import datetime, timedelta

DATASET_TYPE = "SYNTHETIC_RESEARCH_BENCHMARK_COLOMBO_V1"
NUM_TRIPS = 1800
RANDOM_SEED = 42

CORRIDORS = [
    {
        "originZone": "Malabe_Kaduwela",
        "originLat": 6.9040, "originLng": 79.9540,
        "destLot": "SLIIT Innovation Parking Hub",
        "destLat": 6.9147, "destLng": 79.9733,
        "baseDistanceKm": 4.2,
        "bottleneckSeverity": 1.25, # High congestion zone
    },
    {
        "originZone": "Kandy_Road_Kelaniya",
        "originLat": 6.9530, "originLng": 79.9180,
        "destLot": "SLIIT Innovation Parking Hub",
        "destLat": 6.9147, "destLng": 79.9733,
        "baseDistanceKm": 11.8,
        "bottleneckSeverity": 1.30, # Heavy arterial traffic
    },
    {
        "originZone": "Colombo-01_Fort",
        "originLat": 6.9344, "originLng": 79.8428,
        "destLot": "Dutch Hospital Smart Deck",
        "destLat": 6.9325, "destLng": 79.8440,
        "baseDistanceKm": 2.1,
        "bottleneckSeverity": 1.15,
    },
    {
        "originZone": "Colombo-03_Kollupitiya",
        "originLat": 6.8980, "originLng": 79.8530,
        "destLot": "Liberty Plaza Smart Bay",
        "destLat": 6.9030, "destLng": 79.8520,
        "baseDistanceKm": 1.8,
        "bottleneckSeverity": 1.20,
    },
    {
        "originZone": "Nugegoda_Maharagama",
        "originLat": 6.8650, "originLng": 79.8990,
        "destLot": "SLIIT Innovation Parking Hub",
        "destLat": 6.9147, "destLng": 79.9733,
        "baseDistanceKm": 13.5,
        "bottleneckSeverity": 1.22,
    },
    {
        "originZone": "Colombo-01_Fort",
        "originLat": 6.9344, "originLng": 79.8428,
        "destLot": "SLIIT Innovation Parking Hub",
        "destLat": 6.9147, "destLng": 79.9733,
        "baseDistanceKm": 18.2,
        "bottleneckSeverity": 1.28,
    },
    {
        "originZone": "Nugegoda_Maharagama",
        "originLat": 6.8650, "originLng": 79.8990,
        "destLot": "Liberty Plaza Smart Bay",
        "destLat": 6.9030, "destLng": 79.8520,
        "baseDistanceKm": 7.4,
        "bottleneckSeverity": 1.18,
    },
]

def generate_trips(num_trips=NUM_TRIPS, seed=RANDOM_SEED):
    random.seed(seed)
    trips = []

    start_date = datetime(2026, 9, 1, 6, 0) # 2-month simulation window

    for i in range(1, num_trips + 1):
        corridor = random.choice(CORRIDORS)

        # Randomize departure day and time within 60 days
        days_offset = random.randint(0, 59)
        # Weight hours towards daytime and rush hours
        hour_weights = [
            1, 1, 1, 1, 2, 4, 8, 14, 16, 12, 10, 10, 11, 11, 10, 11, 15, 17, 16, 12, 8, 5, 3, 2
        ]
        hour = random.choices(range(24), weights=hour_weights, k=1)[0]
        minute = random.randint(0, 59)
        second = random.randint(0, 59)

        dep_time = start_date + timedelta(days=days_offset, hours=hour, minutes=minute, seconds=second)
        day_of_week = dep_time.isoweekday() # 1=Mon .. 7=Sun
        is_weekend = day_of_week in (6, 7)

        # Sri Lankan Public / Poya holidays (~10% chance)
        is_holiday = random.random() < 0.08

        # Monsoon rain (~20% probability in tropical Colombo)
        is_rain = random.random() < 0.22

        time_decimal = hour + (minute / 60.0)
        is_morning_peak = (not is_weekend) and (not is_holiday) and (7.5 <= time_decimal <= 9.75)
        is_evening_peak = (not is_weekend) and (not is_holiday) and (16.5 <= time_decimal <= 19.5)
        is_peak_hour = is_morning_peak or is_evening_peak

        # Slight variation in route distance
        distance_km = round(corridor["baseDistanceKm"] * random.uniform(0.92, 1.12), 2)

        # 1. Baseline Heuristic calculation (22 km/h city average, straight-line curvature)
        base_speed = 22.0
        base_dur = (distance_km / base_speed) * 60.0
        baseline_cong_mult = 1.35 if is_peak_hour else (1.0 if (time_decimal >= 22 or time_decimal <= 5) else 1.15)
        pred_baseline_min = round(max(3.0, base_dur * baseline_cong_mult), 1)

        # 2. Provider Prediction (nominal OSRM / Google free-flow + typical delay)
        # Commercial providers often underestimate localized Colombo choke points
        free_flow_speed = 36.0
        provider_base = (distance_km / free_flow_speed) * 60.0
        provider_cong = 1.25 if is_peak_hour else 1.05
        pred_provider_min = round(max(3.0, provider_base * provider_cong), 1)

        # 3. Ground-Truth Actual Travel Time (Sri Lankan Real-World Dynamics)
        # Congestion delay factors:
        delay_factor = 1.0

        if is_peak_hour:
            delay_factor += random.uniform(0.25, 0.45)
        elif is_weekend:
            delay_factor -= random.uniform(0.05, 0.15)

        if is_rain:
            # Flooding & three-wheeler bottlenecking adds significant delay
            delay_factor += random.uniform(0.15, 0.35)

        if is_holiday:
            delay_factor -= random.uniform(0.10, 0.22)

        # Corridor bottleneck severity
        delay_factor *= corridor["bottleneckSeverity"] ** 0.65

        # Stochastic urban noise
        noise = random.gauss(0.0, 0.06)
        delay_factor = max(0.65, delay_factor + noise)

        actual_travel_min = round(max(3.0, pred_provider_min * delay_factor), 1)

        # Residual ratio r = actual / provider
        residual_ratio = round(actual_travel_min / pred_provider_min, 4)

        trip = {
            "tripId": f"TRIP-COL-{i:05d}",
            "isSynthetic": True,
            "originZone": corridor["originZone"],
            "destinationLot": corridor["destLot"],
            "distanceKm": distance_km,
            "departureTime": dep_time.isoformat(),
            "dayOfWeek": day_of_week,
            "hour": hour,
            "minute": minute,
            "isPeakHour": 1 if is_peak_hour else 0,
            "isWeekend": 1 if is_weekend else 0,
            "weatherFlag": 1 if is_rain else 0,
            "holidayFlag": 1 if is_holiday else 0,
            "predictedEtaMinBaseline": pred_baseline_min,
            "predictedEtaMinProvider": pred_provider_min,
            "actualTravelMin": actual_travel_min,
            "residualRatio": residual_ratio,
        }
        trips.append(trip)

    return trips

def export_trips(trips, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    csv_path = os.path.join(output_dir, "colombo_trips_synthetic.csv")
    with open(csv_path, mode="w", newline="", encoding="utf-8") as f:
        fieldnames = list(trips[0].keys())
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(trips)

    json_path = os.path.join(output_dir, "colombo_trips_synthetic.json")
    with open(json_path, mode="w", encoding="utf-8") as f:
        json.dump({
            "metadata": {
                "datasetType": DATASET_TYPE,
                "description": "Synthetic Sri Lankan urban trip logs for ETA residual correction model",
                "sampleCount": len(trips),
                "generatedAt": datetime.now().isoformat(),
            },
            "trips": trips,
        }, f, indent=2)

    print(f"[Synthetic Trip Generator] Exported {len(trips)} trips to:")
    print(f"  - CSV:  {csv_path}")
    print(f"  - JSON: {json_path}")

if __name__ == "__main__":
    trips = generate_trips()
    out_dir = os.path.join(os.path.dirname(__file__), "data")
    export_trips(trips, out_dir)
