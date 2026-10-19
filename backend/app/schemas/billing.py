from decimal import Decimal
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class QuoteRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "booking_id": "BK-DEMO",
                "lot_id": "lot-main",
                "entry_time": "2026-10-19T10:00:00+05:30",
                "exit_time": "2026-10-19T11:00:00+05:30",
                "demand_level": "0.5",
            }
        }
    )
    booking_id: str = Field(min_length=1)
    lot_id: str
    entry_time: AwareDatetime
    exit_time: AwareDatetime
    demand_level: Decimal | None = Field(default=None, ge=0, le=1)
    extension_minutes: int = Field(default=0, ge=0)
    arrival_extension_fee: int = Field(default=0, ge=0, strict=True)
    upgrade_from_slot_id: str | None = None
    upgrade_to_slot_id: str | None = None


class LineItem(BaseModel):
    label: str
    qty: int
    unit: str
    amount: int


class FeeQuote(BaseModel):
    booking_id: str
    entry_time: AwareDatetime
    exit_time: AwareDatetime
    line_items: list[LineItem]
    subtotal: int
    surge_amount: int
    total: int
    currency: str = "LKR"
    explanation: str


class CreateInvoiceRequest(BaseModel):
    booking_id: str = Field(min_length=1)
    quote: FeeQuote


class Invoice(BaseModel):
    model_config = ConfigDict(frozen=True)
    id: str
    booking_id: str
    quote: FeeQuote
    status: Literal["pending", "awaiting_guard", "paid", "failed"] = "pending"


class PaymentRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": {"method": "payhere"}})
    method: Literal["payhere", "stripe", "guard"]


class PaymentSession(BaseModel):
    model_config = ConfigDict(frozen=True)
    id: str
    invoice_id: str
    method: Literal["payhere", "stripe", "guard"]
    provider: Literal["payhere", "stripe", "mock", "guard", "free"]
    status: Literal["pending", "awaiting_guard", "paid", "failed"]
    is_mock: bool
    amount_minor: int = Field(ge=0)
    currency: str
    provider_payment_id: str | None = None
    checkout_url: str | None = None
    checkout_fields: dict[str, str] = Field(default_factory=dict)
    client_secret: str | None = None
    mock_webhook_token: str | None = None
    message: str


class ExitGrant(BaseModel):
    """Stored token ledger entry; only the public subset is returned by routes."""

    nonce: str
    invoice_id: str
    token: str
    expires_at: AwareDatetime
    used_at: AwareDatetime | None = None


class ExitToken(BaseModel):
    invoice_id: str
    token: str
    expires_at: AwareDatetime
    is_mock: bool = False


class ConsumeExitTokenRequest(BaseModel):
    token: str = Field(min_length=1, max_length=4096)
