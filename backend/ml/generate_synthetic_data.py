"""SYNTHETIC demonstration data; not observations from SLIIT or CCTV.

Dictionary: timestamp = aware ISO-8601 hour; lot_id = Flutter mock lot ID;
occupied_slots = integer parked vehicles, 0..capacity; capacity = mock slot count;
entries = synthetic hourly arrivals (not a vehicle-conservation ledger);
rain_mm = synthetic hourly rainfall in mm; event_flag = simulated event (0/1).
"""

import argparse
import re
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA = Path(__file__).parent / "data" / "synthetic_occupancy.csv"


def read_mock_lots(
    path: Path = ROOT / "lib/data/services/mock_data.dart",
) -> dict[str, int]:
    """Read only lot declarations, not slot IDs or historical booking IDs."""
    source = path.read_text().split("static List<ParkingLot> getInitialLots()", 1)[1]
    source = source.split("static List<Booking>", 1)[0]
    matches = re.findall(r"id:\s*'(lot-[^']+)'.*?totalSlots:\s*(\d+)", source, re.S)
    lots = {lot_id: int(capacity) for lot_id, capacity in matches}
    if not lots or any(capacity <= 0 for capacity in lots.values()):
        raise ValueError("Could not read positive lot capacities from Flutter mocks")
    return lots


def generate(days: int = 90, seed: int = 335) -> pd.DataFrame:
    if days < 1:
        raise ValueError("Days must be positive")
    rng = np.random.default_rng(seed)
    times = pd.date_range("2026-07-01", periods=days * 24, freq="h", tz="Asia/Colombo")
    rain = np.where(
        rng.random(len(times)) < 0.18, rng.gamma(2, 2, len(times)), 0
    ).round(2)
    events = ((times.dayofweek == 2) & (times.hour >= 11) & (times.hour <= 15)).astype(
        int
    )
    rows = []
    for index, (lot_id, capacity) in enumerate(read_mock_lots().items()):
        hour = times.hour.to_numpy()
        peaks = 0.42 * np.exp(-(((hour - 8) / 2.1) ** 2)) + 0.36 * np.exp(
            -(((hour - 13) / 2.8) ** 2)
        )
        weekday = np.where(times.dayofweek < 5, 1.0, 0.42)
        # Days 49..62 simulate a semester break, not an official campus calendar.
        break_factor = np.where(
            (np.arange(len(times)) // 24 >= 49) & (np.arange(len(times)) // 24 < 63),
            0.58,
            1.0,
        )
        level = (
            (0.12 + peaks + index * 0.035) * weekday * break_factor
            - 0.008 * rain
            + 0.12 * events
            + rng.normal(0, 0.045, len(times))
        )
        occupied = np.rint(np.clip(level, 0, 1) * capacity).astype(int)
        entries = rng.poisson(np.maximum(0.1, occupied * 0.22))
        for offset, ts in enumerate(times):
            rows.append(
                {
                    "timestamp": ts.isoformat(),
                    "lot_id": lot_id,
                    "occupied_slots": int(occupied[offset]),
                    "capacity": capacity,
                    "entries": int(entries[offset]),
                    "rain_mm": float(rain[offset]),
                    "event_flag": int(events[offset]),
                }
            )
    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=90)
    parser.add_argument("--seed", type=int, default=335)
    parser.add_argument("--output", type=Path, default=DEFAULT_DATA)
    args = parser.parse_args()
    data = generate(args.days, args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data.to_csv(args.output, index=False)
    print(f"SYNTHETIC: {len(data)} hourly rows → {args.output}")


if __name__ == "__main__":
    main()
