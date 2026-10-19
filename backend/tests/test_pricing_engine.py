from datetime import datetime, timedelta
from decimal import Decimal

import pytest

from app.services.pricing_engine import calculate_quote, whole_lkr


def quote(
    start="2026-10-19T10:00:00+05:30", minutes=60, rate="100", demand="0", **kwargs
):
    entry = datetime.fromisoformat(start)
    return calculate_quote(
        entry_time=entry,
        exit_time=entry + timedelta(minutes=minutes),
        lot_hourly_rate=Decimal(rate),
        demand_level=Decimal(demand),
        **kwargs,
    )


@pytest.mark.parametrize(
    "minutes,total", [(1, 0), (10, 0), (11, 25), (60, 100), (61, 125)]
)
def test_grace_hour_and_block_rounding(minutes, total):
    assert quote(minutes=minutes)["total"] == total


def test_partial_peak_overlap():
    # 30 peak minutes out of a one-hour stay: 100 + 30/60 * 100 * .25.
    result = quote(start="2026-10-19T07:00:00+05:30")
    assert result["total"] == 113


def test_padding_is_not_peak_time():
    # Actual peak overlap is one minute; the padded 14 minutes are normal-rate.
    assert quote(start="2026-10-19T07:15:00+05:30", minutes=16)["total"] == 50


def test_daily_cap_applies_after_surge():
    assert (
        quote(start="2026-10-19T00:00:00+05:30", minutes=1000, demand="1")["total"]
        == 1200
    )


@pytest.mark.parametrize(
    "demand,total",
    [("0.59", 100), ("0.6", 100), ("0.9", 150), ("1.0", 150), ("0.75", 125)],
)
def test_surge_boundaries(demand, total):
    assert quote(demand=demand)["total"] == total


def test_extension_is_premium_on_recorded_minutes():
    # 60 minutes already include 20 minutes of overtime: 100 + 16.666...
    assert quote(extension_minutes=20)["total"] == 117


def test_upgrade_delta_for_remaining_time():
    assert quote(upgrade_rate_delta=Decimal("40"), upgrade_minutes=30)["total"] == 120


@pytest.mark.parametrize("minutes", [0, -1])
def test_invalid_exit(minutes):
    with pytest.raises(ValueError, match="Exit"):
        quote(minutes=minutes)


def test_multi_day_caps_reset_at_local_midnight():
    # Two full Colombo days: each is capped independently.
    assert quote(start="2026-10-19T00:00:00+05:30", minutes=2880)["total"] == 2400


def test_weekend_has_no_peak():
    assert quote(start="2026-10-18T08:00:00+05:30")["total"] == 100


def test_both_weekday_peak_windows():
    assert quote(start="2026-10-19T15:30:00+05:30")["total"] == 125


def test_half_up_rounding():
    assert whole_lkr(Decimal("12.5")) == 13
    assert quote(minutes=15, rate="50")["total"] == 13


def test_naive_timestamp_rejected():
    with pytest.raises(ValueError, match="timezone"):
        quote(start="2026-10-19T10:00:00")


@pytest.mark.parametrize(
    "kwargs",
    [
        {"demand": "1.01"},
        {"demand": "-0.1"},
        {"rate": "-1"},
        {"rate": "NaN"},
        {"extension_minutes": -1},
        {"extension_minutes": 61},
        {"upgrade_minutes": 61},
        {"upgrade_rate_delta": Decimal("-1")},
    ],
)
def test_invalid_values(kwargs):
    with pytest.raises(ValueError):
        quote(**kwargs)


def test_equivalent_timezone_inputs_and_calendar_boundary():
    colombo = quote(start="2026-10-19T23:45:00+05:30", minutes=30)
    utc = quote(start="2026-10-19T18:15:00+00:00", minutes=30)
    assert colombo == utc
    assert colombo["total"] == 50


@pytest.mark.parametrize(
    "kwargs",
    [
        {},
        {"demand": "0.75"},
        {"minutes": 1000, "demand": "1"},
        {"start": "2026-10-19T23:45:00+05:30", "minutes": 30},
        {
            "extension_minutes": 15,
            "upgrade_rate_delta": Decimal("15"),
            "upgrade_minutes": 10,
        },
    ],
)
def test_line_items_reconcile(kwargs):
    result = quote(**kwargs)
    assert sum(item["amount"] for item in result["line_items"]) == result["total"]
    assert result["subtotal"] + result["surge_amount"] == result["total"]
    assert isinstance(result["total"], int)


def test_arrival_extension_fee_is_preserved_without_inventing_overtime():
    assert quote(arrival_extension_fee=50)["total"] == 150
    assert quote(demand="0.9", arrival_extension_fee=50)["total"] == 200
    assert quote(minutes=5, arrival_extension_fee=50)["total"] == 50


def test_arrival_extension_is_once_and_inside_entry_day_cap():
    result = quote(
        start="2026-10-19T00:00:00+05:30", minutes=2880, arrival_extension_fee=50
    )
    assert result["total"] == 2400
    items = [
        item
        for item in result["line_items"]
        if item["label"] == "Arrival deadline extension"
    ]
    assert len(items) == 1 and items[0]["amount"] == 50
    assert sum(item["amount"] for item in result["line_items"]) == result["total"]


@pytest.mark.parametrize("fee", [-1, 1.5, True])
def test_invalid_arrival_extension_fee(fee):
    with pytest.raises(ValueError, match="whole LKR"):
        quote(arrival_extension_fee=fee)


def test_shared_dart_pricing_fixtures_match_backend():
    import json
    from pathlib import Path

    path = Path(__file__).resolve().parents[2] / "test/billing/pricing_cases.json"
    for case in json.loads(path.read_text()):
        result = calculate_quote(
            entry_time=datetime.fromisoformat(case["entry"]),
            exit_time=datetime.fromisoformat(case["exit"]),
            lot_hourly_rate=Decimal(case["rate"]),
            demand_level=Decimal(case["demand"]),
            extension_minutes=case["extension_minutes"],
            arrival_extension_fee=case["arrival_fee"],
        )
        assert result["total"] == case["total"], case["name"]
        assert result["subtotal"] == case["subtotal"], case["name"]
        assert result["surge_amount"] == case["surge_amount"], case["name"]
