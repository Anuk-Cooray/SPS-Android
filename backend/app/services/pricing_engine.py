"""Pure provisional tariff calculation. All money uses Decimal, never float."""

from datetime import datetime, time, timedelta
from decimal import ROUND_CEILING, ROUND_HALF_UP, Decimal
from zoneinfo import ZoneInfo

COLOMBO = ZoneInfo("Asia/Colombo")
RULES = {
    "block_minutes": 15,
    "grace_minutes": 10,
    "peak_multiplier": Decimal("1.25"),
    "peak_windows": ((time(7, 30), time(9, 30)), (time(15, 30), time(17, 30))),
    "surge_start": Decimal("0.6"),
    "surge_full": Decimal("0.9"),
    "surge_cap": Decimal("1.5"),
    "daily_cap": Decimal("1200"),
    "extension_multiplier": Decimal("1.5"),
}


def whole_lkr(amount: Decimal) -> int:
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def minutes_between(start: datetime, end: datetime) -> Decimal:
    delta = end - start
    return Decimal(delta // timedelta(microseconds=1)) / Decimal("60000000")


def overlap_minutes(
    start: datetime, end: datetime, left: datetime, right: datetime
) -> Decimal:
    return max(Decimal(0), minutes_between(max(start, left), min(end, right)))


def demand_multiplier(level: Decimal) -> Decimal:
    if not level.is_finite() or not Decimal(0) <= level <= Decimal(1):
        raise ValueError("Demand must be between zero and one")
    fraction = max(Decimal(0), level - RULES["surge_start"]) / (
        RULES["surge_full"] - RULES["surge_start"]
    )
    return min(RULES["surge_cap"], Decimal(1) + fraction * (RULES["surge_cap"] - 1))


def calculate_quote(
    *,
    entry_time: datetime,
    exit_time: datetime,
    lot_hourly_rate: Decimal,
    demand_level: Decimal = Decimal(0),
    extension_minutes: int = 0,
    arrival_extension_fee: int = 0,
    upgrade_rate_delta: Decimal = Decimal(0),
    upgrade_minutes: int = 0,
) -> dict:
    """Extension/upgrade minutes are trailing portions of the recorded stay.

    Round each calendar day's stay to blocks; padding is charged at the normal
    rate. Peak and overtime premiums apply only to actual overlapping minutes.
    Surge applies to all charges before the calendar-day cap. Round money once
    per day and allocate the rounding remainder to the surge/cap adjustment.
    """
    if entry_time.utcoffset() is None or exit_time.utcoffset() is None:
        raise ValueError("Entry and exit must include a timezone")
    start, end = entry_time.astimezone(COLOMBO), exit_time.astimezone(COLOMBO)
    if end <= start:
        raise ValueError("Exit must follow entry")
    if any(
        not value.is_finite() or value < 0
        for value in (lot_hourly_rate, upgrade_rate_delta)
    ):
        raise ValueError("Rates must be finite and non-negative")
    duration = minutes_between(start, end)
    if not 0 <= extension_minutes <= duration or not 0 <= upgrade_minutes <= duration:
        raise ValueError("Extension and upgrade durations must fit within the stay")
    if type(arrival_extension_fee) is not int or arrival_extension_fee < 0:
        raise ValueError("Arrival extension fee must be non-negative whole LKR")
    multiplier = demand_multiplier(demand_level)
    items: list[dict] = []
    subtotal = total = 0
    if duration <= RULES["grace_minutes"]:
        items.append({"label": "Grace period", "qty": 1, "unit": "stay", "amount": 0})
        if arrival_extension_fee:
            subtotal = arrival_extension_fee
            total = whole_lkr(min(RULES["daily_cap"], Decimal(arrival_extension_fee)))
            items.append(
                {
                    "label": "Arrival deadline extension",
                    "qty": 1,
                    "unit": "booked fee",
                    "amount": subtotal,
                }
            )
            if total != subtotal:
                items.append(
                    {
                        "label": "Daily cap adjustment",
                        "qty": 1,
                        "unit": "adjustment",
                        "amount": total - subtotal,
                    }
                )
    else:
        cursor = start
        while cursor < end:
            midnight = datetime.combine(
                cursor.date() + timedelta(days=1), time(), COLOMBO
            )
            day_end = min(midnight, end)
            minutes = minutes_between(cursor, day_end)
            blocks = (minutes / RULES["block_minutes"]).to_integral_value(
                rounding=ROUND_CEILING
            )
            base = blocks * RULES["block_minutes"] * lot_hourly_rate / 60
            peak_minutes = Decimal(0)
            if cursor.weekday() < 5:
                for left, right in RULES["peak_windows"]:
                    peak_minutes += overlap_minutes(
                        cursor,
                        day_end,
                        datetime.combine(cursor.date(), left, COLOMBO),
                        datetime.combine(cursor.date(), right, COLOMBO),
                    )
            peak = peak_minutes * lot_hourly_rate / 60 * (RULES["peak_multiplier"] - 1)
            overtime = overlap_minutes(
                cursor, day_end, end - timedelta(minutes=extension_minutes), end
            )
            extension = (
                overtime * lot_hourly_rate / 60 * (RULES["extension_multiplier"] - 1)
            )
            upgraded = overlap_minutes(
                cursor, day_end, end - timedelta(minutes=upgrade_minutes), end
            )
            upgrade = upgraded * upgrade_rate_delta / 60
            day_subtotal = sum(map(whole_lkr, (base, peak, extension, upgrade)))
            arrival_fee = arrival_extension_fee if cursor == start else 0
            day_subtotal += arrival_fee
            raw = base + peak + extension + upgrade
            day_total = whole_lkr(
                min(RULES["daily_cap"], raw * multiplier + arrival_fee)
            )
            prefix = cursor.date().isoformat()
            for label, quantity, unit, amount in (
                ("Parking", int(blocks), "15-minute block", whole_lkr(base)),
                ("Peak premium", 1, "overlap", whole_lkr(peak)),
                ("Overtime premium", 1, "overlap", whole_lkr(extension)),
                ("Upgrade", 1, "overlap", whole_lkr(upgrade)),
            ):
                if label == "Parking" or amount:
                    items.append(
                        {
                            "label": f"{prefix} {label}",
                            "qty": quantity,
                            "unit": unit,
                            "amount": amount,
                        }
                    )
            if arrival_fee:
                items.append(
                    {
                        "label": "Arrival deadline extension",
                        "qty": 1,
                        "unit": "booked fee",
                        "amount": arrival_fee,
                    }
                )
            adjustment = day_total - day_subtotal
            if adjustment:
                items.append(
                    {
                        "label": f"{prefix} Surge / daily cap / rounding",
                        "qty": 1,
                        "unit": "adjustment",
                        "amount": adjustment,
                    }
                )
            subtotal += day_subtotal
            total += day_total
            cursor = day_end
    return {
        "line_items": items,
        "subtotal": subtotal,
        "surge_amount": total - subtotal,
        "total": total,
        "currency": "LKR",
        "explanation": "Provisional tariff: 10-minute stay grace; each Colombo day rounds up to 15-minute blocks. "
        "Peak and overtime premiums apply only to actual minutes. Extension is part of the stay, not additional time. "
        "Surge applies before the LKR 1200 daily cap. Surge amount includes cap and rounding adjustments. "
        "A booked arrival-deadline fee is added once on the entry day, without surge, within that day cap.",
    }
