
import os
from pathlib import Path
from typing import Annotated

import joblib
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


# --------------------------------------------------
# Configuration
# --------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "ble_first_floor_extra_trees_77.pkl"

app = FastAPI(
    title="AI Vision-Based Smart Parking API",
    description=(
        "Backend APIs for QR barrier authorization "
        "and GPS-free Find My Car sector prediction."
    ),
    version="1.0.0",
)

# Development configuration.
# Restrict allowed origins before production deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5000",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# --------------------------------------------------
# Load the trained machine-learning model
# --------------------------------------------------

model = None

if MODEL_PATH.is_file():
    try:
        model = joblib.load(MODEL_PATH)
        print(f"ML model loaded: {MODEL_PATH}")
    except Exception as exc:
        print(f"WARNING: Could not load ML model: {exc}")
else:
    print(
        "WARNING: ML model not found. "
        "Place ble_first_floor_extra_trees_77.pkl "
        "inside the backend folder."
    )


# --------------------------------------------------
# Request models
# --------------------------------------------------

class BarrierVerifyRequest(BaseModel):
    booking_id: Annotated[str, Field(min_length=1, max_length=100)]
    qr_token: Annotated[str, Field(min_length=1, max_length=500)]


class FindMyCarRequest(BaseModel):
    # RSSI values must be ordered B1, B2, B3, B4, B5, B6.
    rssi: Annotated[
        list[float],
        Field(min_length=6, max_length=6),
    ]


# --------------------------------------------------
# Temporary development booking
# --------------------------------------------------
# IMPORTANT:
# This is only a test record, NOT real authentication.
# Replace it with database-backed booking verification.
#
# Never use a hardcoded QR token to secure a real barrier.

DEMO_BOOKINGS = {
    "DEMO-BOOKING-001": "DEMO-QR-TOKEN-001",
}


# --------------------------------------------------
# Health check
# --------------------------------------------------

@app.get("/")
def root():
    return {
        "message": "Smart Parking API is running",
        "docs": "/docs",
        "model_loaded": model is not None,
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": model is not None,
    }


# --------------------------------------------------
# QR barrier verification
# --------------------------------------------------

@app.post("/api/barrier/verify")
def verify_barrier(request: BarrierVerifyRequest):
    """
    Development-only verification.

    This checks a temporary demo booking and does NOT
    command or confirm the physical ESP32 barrier.
    """

    expected_token = DEMO_BOOKINGS.get(request.booking_id)

    authorized = (
        expected_token is not None
        and request.qr_token == expected_token
    )

    if not authorized:
        return {
            "authorized": False,
            "barrier_opened": False,
            "message": "Invalid booking ID or QR token.",
        }

    # No ESP32 is connected yet. Never report that the
    # physical barrier opened when it has not been tested.
    return {
        "authorized": True,
        "barrier_opened": False,
        "message": (
            "Demo verification successful. "
            "ESP32 barrier control is not connected yet."
        ),
    }


# --------------------------------------------------
# Find My Car: ML sector prediction
# --------------------------------------------------

@app.post("/api/navigation/predict-sector")
def predict_sector(request: FindMyCarRequest):
    """
    Predict a sector from six BLE RSSI values.

    Input order: B1, B2, B3, B4, B5, B6.
    The model predicts among its trained first-floor
    classes; it does not calculate a walking route.
    """

    if model is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "ML model is not loaded. "
                "Place the trained .pkl file inside backend."
            ),
        )

    values = np.asarray(request.rssi, dtype=float)

    if not np.all(np.isfinite(values)):
        raise HTTPException(
            status_code=422,
            detail="RSSI values must be finite numbers.",
        )

    try:
        prediction = model.predict(values.reshape(1, 6))[0]
    except Exception as exc:
        print(f"Prediction error: {exc}")
        raise HTTPException(
            status_code=500,
            detail="Unable to predict the parking sector.",
        ) from exc

    return {
        "predicted_sector": int(prediction),
        "floor": 1,
        "model": "ExtraTreesClassifier",
        "input_order": ["B1", "B2", "B3", "B4", "B5", "B6"],
        "message": "Sector prediction completed.",
    }


# --------------------------------------------------
# Run with:
# python -m uvicorn main:app --reload
# --------------------------------------------------
