"""Demo lot registry mirrors Flutter mock_data.dart; no database yet."""

import os
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from dotenv import load_dotenv

LOT_RATES = {
    "lot-main": Decimal(100),
    "lot-new-p2": Decimal(80),
    "lot-sports": Decimal(50),
}


def is_debug() -> bool:
    """Explicit process environment flag; never enabled by default."""
    load_dotenv(Path(__file__).resolve().parents[2] / ".env", override=False)
    return os.getenv("DEBUG", "false").strip().lower() == "true"


@dataclass(frozen=True)
class PaymentSettings:
    payhere_merchant_id: str = ""
    payhere_secret: str = field(default="", repr=False)
    public_base_url: str = ""
    stripe_key: str = field(default="", repr=False)
    stripe_webhook_secret: str = field(default="", repr=False)
    stripe_currency: str = "lkr"
    usd_per_lkr: Decimal | None = None

    @classmethod
    def from_env(cls) -> "PaymentSettings":
        load_dotenv(Path(__file__).resolve().parents[2] / ".env", override=False)
        rate = os.getenv("STRIPE_USD_PER_LKR", "").strip()
        from app.services.payments.base import PaymentError

        try:
            conversion = Decimal(rate) if rate else None
            if conversion is not None and (
                not conversion.is_finite() or conversion <= 0
            ):
                raise ValueError("Invalid exchange rate")
        except (ValueError, ArithmeticError) as error:
            raise PaymentError(
                "PAYMENT_CONFIG",
                "STRIPE_USD_PER_LKR must be a finite positive decimal",
                503,
            ) from error
        return cls(
            payhere_merchant_id=os.getenv("PAYHERE_MERCHANT_ID", "").strip(),
            payhere_secret=os.getenv("PAYHERE_MERCHANT_SECRET", "").strip(),
            public_base_url=os.getenv("PUBLIC_BASE_URL", "").strip(),
            stripe_key=os.getenv("STRIPE_SECRET_KEY", "").strip(),
            stripe_webhook_secret=os.getenv("STRIPE_WEBHOOK_SECRET", "").strip(),
            stripe_currency=os.getenv("STRIPE_CURRENCY", "lkr").strip().lower(),
            usd_per_lkr=conversion,
        )
