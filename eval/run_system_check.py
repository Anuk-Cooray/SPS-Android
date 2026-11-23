"""
Smart Parking System (SLIIT J26-IT-335)
System Check Replay Harness: Real Cloud Functions vs Python Simulation

Replays ~200 trips through the real Cloud Functions / server authority
and validates that resulting KPIs match the Python simulation within 5%.
"""

import sys
import json
import math
import random
import urllib.request
import urllib.error
import subprocess
from pathlib import Path
from typing import Dict, Any, List

from eval.config_loader import load_config
from eval.policies import FullDynamicPolicy
from eval.simulation_engine import generate_trip_stream, run_simulation

EMULATOR_BASE_URL = "http://127.0.0.1:5001/sps-android/us-central1"

def check_emulator_online() -> bool:
    try:
        req = urllib.request.Request(f"{EMULATOR_BASE_URL}/ingestOccupancy", method="GET")
        with urllib.request.urlopen(req, timeout=1.0) as resp:
            return True
    except urllib.error.HTTPError as e:
        # HTTP 405 Method Not Allowed means endpoint is online!
        return e.code == 405
    except Exception:
        return False

def run_system_replay(trips: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, Any]:
    """
    Replays 200 trips through the real Cloud Functions logic via Node.js runtime script
    or HTTP emulator endpoints.
    """
    print("Executing system replay against TypeScript / Cloud Functions server authority...")

    # We invoke Node.js runner script that executes the exact compiled logic
    runner_script = Path(__file__).parent / "node_replay_runner.js"

    # Write trip payloads for Node runner
    trips_payload_path = Path(__file__).parent / "results" / "system_check_trips.json"
    with open(trips_payload_path, "w", encoding="utf-8") as f:
        json.dump({"trips": trips, "config": config}, f)

    cmd = ["node", str(runner_script), str(trips_payload_path)]
    res = subprocess.run(cmd, capture_output=True, text=True, cwd=str(Path(__file__).parent.parent / "functions"))

    if res.returncode != 0:
        print(f"Node replay stderr: {res.stderr}")
        raise RuntimeError(f"System replay failed with code {res.returncode}")

    output_json = json.loads(res.stdout.strip())
    return output_json

def main():
    base_dir = Path(__file__).parent
    config_path = base_dir / "config.yaml"
    config = load_config(config_path)

    print("--- SLIIT J26-IT-335: System Parity & Replay Verification ---")

    # Generate fixed stream of 200 trips
    seed = 20261019
    raw_trips = generate_trip_stream(seed=seed, config=config)
    eval_trips = raw_trips[:200]
    print(f"Generated {len(eval_trips)} standardized trips (seed={seed})")

    # 1. Run Python Reference Simulation
    print("\n1. Running Reference Python D3 Dynamic Simulation...")
    py_policy = FullDynamicPolicy()
    py_kpis = run_simulation(policy=py_policy, trips=eval_trips, config=config)
    print(f"  Python Sim Rejection Rate:         {py_kpis['rejection_rate_pct']:.2f}%")
    print(f"  Python Sim Mean Walking Distance:  {py_kpis['mean_walking_distance_m']:.2f} m")
    print(f"  Python Sim Distance Saved Mean:    {py_kpis['walking_distance_saved_mean_m']:.2f} m")

    # 2. Run Real System Replay (TypeScript Server Authority)
    print("\n2. Running Real Cloud Functions Server Authority Replay...")
    sys_kpis = run_system_replay(eval_trips, config)
    print(f"  Server Replay Rejection Rate:       {sys_kpis['rejection_rate_pct']:.2f}%")
    print(f"  Server Replay Mean Walking Dist:    {sys_kpis['mean_walking_distance_m']:.2f} m")
    print(f"  Server Replay Distance Saved Mean:  {sys_kpis['walking_distance_saved_mean_m']:.2f} m")

    # 3. Parity Delta & Within 5% Validation
    print("\n3. Validating KPI Parity (Tolerance <= 5%):")
    passed = True

    for kpi in ["rejection_rate_pct", "mean_walking_distance_m", "walking_distance_saved_mean_m"]:
        py_val = py_kpis[kpi]
        sys_val = sys_kpis[kpi]

        if py_val == 0.0 and sys_val == 0.0:
            pct_delta = 0.0
        elif py_val == 0.0:
            pct_delta = abs(sys_val)
        else:
            pct_delta = abs(sys_val - py_val) / py_val * 100.0

        within_5_pct = pct_delta <= 5.0
        status = "PASS" if within_5_pct else "FAIL"
        print(f"  - {kpi}: Python={py_val:.2f}, System={sys_val:.2f}, Delta={pct_delta:.2f}% -> [{status}]")

        if not within_5_pct:
            passed = False

    if passed:
        print("\nSUCCESS: Real Cloud Functions server replay matches Python simulation within 5%!")
        sys.exit(0)
    else:
        print("\nFAILURE: One or more KPIs exceeded 5% delta threshold between sim and server.")
        sys.exit(1)

if __name__ == "__main__":
    main()
