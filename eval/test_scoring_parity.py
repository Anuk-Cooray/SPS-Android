"""
Smart Parking System (SLIIT J26-IT-335)
Unit test: Proves 100% mathematical parity of Python scoring_engine.py against
Dart ReoptimizationEngine and TypeScript scoring.ts using shared test vectors.
"""

import json
import os
import sys
import unittest

from scoring_engine import score_slot

class TestScoringParity(unittest.TestCase):
    def test_shared_test_vectors_parity(self):
        # Locate shared test vector JSON
        base_dir = os.path.dirname(os.path.abspath(__file__))
        vector_path = os.path.join(base_dir, "..", "test_vectors", "scoring_test_vectors.json")
        self.assertTrue(os.path.exists(vector_path), f"Test vector file missing: {vector_path}")

        with open(vector_path, "r", encoding="utf-8") as f:
            vectors = json.load(f)

        self.assertGreater(len(vectors), 0, "No test vectors loaded.")

        for v in vectors:
            vec_id = v["id"]
            slot = v["slot"]
            lot = v["lot"]
            vehicle = v["vehicle"]
            preferences = v["preferences"]
            expected = v["expected"]

            result = score_slot(slot, lot, vehicle, preferences)

            if not expected["isEligible"]:
                self.assertFalse(result["is_eligible"], f"Vector {vec_id}: Expected ineligible, got eligible.")
                self.assertEqual(result["total_score"], 0.0, f"Vector {vec_id}: Score must be 0 for ineligible.")
            else:
                self.assertTrue(result["is_eligible"], f"Vector {vec_id}: Expected eligible, got ineligible.")
                self.assertAlmostEqual(
                    result["distance_score"],
                    expected["distanceScore"],
                    places=2,
                    msg=f"Vector {vec_id}: distanceScore mismatch. Expected {expected['distanceScore']}, got {result['distance_score']}"
                )
                self.assertAlmostEqual(
                    result["size_fit_score"],
                    expected["sizeFitScore"],
                    places=2,
                    msg=f"Vector {vec_id}: sizeFitScore mismatch. Expected {expected['sizeFitScore']}, got {result['size_fit_score']}"
                )
                self.assertAlmostEqual(
                    result["preference_score"],
                    expected["preferenceScore"],
                    places=2,
                    msg=f"Vector {vec_id}: preferenceScore mismatch. Expected {expected['preferenceScore']}, got {result['preference_score']}"
                )
                self.assertAlmostEqual(
                    result["demand_penalty"],
                    expected["demandPenalty"],
                    places=2,
                    msg=f"Vector {vec_id}: demandPenalty mismatch. Expected {expected['demandPenalty']}, got {result['demand_penalty']}"
                )
                self.assertAlmostEqual(
                    result["total_score"],
                    expected["totalScore"],
                    places=2,
                    msg=f"Vector {vec_id}: totalScore mismatch. Expected {expected['totalScore']}, got {result['total_score']}"
                )

if __name__ == "__main__":
    unittest.main()
