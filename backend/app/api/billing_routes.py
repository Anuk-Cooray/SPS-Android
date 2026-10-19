import hmac
import os
from datetime import timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import PlainTextResponse

from app.core.config import LOT_RATES, is_debug
from app.schemas.billing import (
    ConsumeExitTokenRequest,
    CreateInvoiceRequest,
    ExitToken,
    FeeQuote,
    Invoice,
    PaymentRequest,
    PaymentSession,
    QuoteRequest,
)
from app.services.exit_token_service import ExitTokenService
from app.services.forecast_service import ForecastService, get_forecast_service
from app.services.invoice_service import InvoiceService, get_invoice_service
from app.services.payments.base import PaymentError, WebhookRequest
from app.services.pricing_engine import calculate_quote, minutes_between

router = APIRouter(prefix="/billing", tags=["billing"])


@router.post("/quote", response_model=FeeQuote)
def quote_fee(
    request: QuoteRequest,
    forecast: Annotated[ForecastService, Depends(get_forecast_service)],
    invoices: Annotated[InvoiceService, Depends(get_invoice_service)],
) -> FeeQuote:
    if request.lot_id not in LOT_RATES:
        raise HTTPException(
            404, detail={"code": "LOT_NOT_FOUND", "message": "Unknown lot"}
        )
    if (request.upgrade_from_slot_id is None) != (request.upgrade_to_slot_id is None):
        raise HTTPException(
            422,
            detail={
                "code": "INVALID_UPGRADE",
                "message": "Provide both upgrade slot IDs",
            },
        )
    if request.exit_time <= request.entry_time:
        raise HTTPException(
            422, detail={"code": "INVALID_QUOTE", "message": "Exit must follow entry"}
        )
    if request.extension_minutes > minutes_between(
        request.entry_time, request.exit_time
    ):
        raise HTTPException(
            422,
            detail={
                "code": "INVALID_QUOTE",
                "message": "Extension duration must fit within the stay",
            },
        )
    level = request.demand_level
    source = "Explicit demand override (demo only)."
    if level is None:
        level, hour = forecast.demand_for_hour(request.lot_id, request.exit_time)
        source = f"Synthetic forecast demand {level} for exit hour {hour.isoformat()}; one multiplier for this quote."
    try:
        result = calculate_quote(
            entry_time=request.entry_time,
            exit_time=request.exit_time,
            lot_hourly_rate=LOT_RATES[request.lot_id],
            demand_level=level,
            extension_minutes=request.extension_minutes,
            arrival_extension_fee=request.arrival_extension_fee,
        )
    except ValueError as error:
        raise HTTPException(
            422, detail={"code": "INVALID_QUOTE", "message": str(error)}
        ) from error
    if request.upgrade_from_slot_id is not None:
        result["line_items"].append(
            {
                "label": f"Upgrade {request.upgrade_from_slot_id} → {request.upgrade_to_slot_id}",
                "qty": 1,
                "unit": "upgrade",
                "amount": 0,
            }
        )
        source += " Recorded slot upgrade has no authoritative rate delta; no upgrade charge applied."
    result["explanation"] += " " + source
    quote = FeeQuote(
        booking_id=request.booking_id,
        entry_time=request.entry_time.astimezone(timezone.utc),
        exit_time=request.exit_time.astimezone(timezone.utc),
        **result,
    )

    invoices.remember_quote(quote)
    return quote


InvoiceDependency = Annotated[InvoiceService, Depends(get_invoice_service)]


@router.post("/invoices", response_model=Invoice)
def create_invoice(
    request: CreateInvoiceRequest, service: InvoiceDependency
) -> Invoice:
    return service.create_invoice(request.booking_id, request.quote)


@router.get("/invoices/{invoice_id}", response_model=Invoice)
def get_invoice(invoice_id: str, service: InvoiceDependency) -> Invoice:
    return service.get_invoice(invoice_id)


@router.post("/invoices/{invoice_id}/pay", response_model=PaymentSession)
def pay_invoice(
    invoice_id: str, request: PaymentRequest, service: InvoiceDependency
) -> PaymentSession:
    return service.start_payment(invoice_id, request.method)


@router.post("/webhooks/payhere")
async def payhere_webhook(request: Request, service: InvoiceDependency) -> dict:
    return service.handle_webhook(
        "payhere", WebhookRequest(await request.body(), request.headers)
    )


@router.post("/webhooks/stripe")
async def stripe_webhook(request: Request, service: InvoiceDependency) -> dict:
    return service.handle_webhook(
        "stripe", WebhookRequest(await request.body(), request.headers)
    )


@router.post(
    "/webhooks/mock",
    description="DEBUG-only offline simulation; never confirms a real provider session.",
)
async def mock_webhook(request: Request, service: InvoiceDependency) -> dict:
    if not is_debug():
        raise PaymentError(
            "DEBUG_REQUIRED", "Mock confirmation requires DEBUG=true", 403
        )
    return service.handle_webhook(
        "mock", WebhookRequest(await request.body(), request.headers)
    )


@router.get("/payment-return", response_class=PlainTextResponse)
def payment_return() -> str:
    return "Sandbox checkout returned. Return to the app and refresh the invoice. This redirect does not confirm payment."


@router.get("/bookings/{booking_id}/invoice", response_model=Invoice)
def booking_invoice(booking_id: str, service: InvoiceDependency) -> Invoice:
    invoice = service.repository.find_booking_invoice(booking_id)
    if invoice is None:
        raise PaymentError("INVOICE_NOT_FOUND", "Invoice not found", 404)
    return invoice


@router.get("/invoices/{invoice_id}/exit-token", response_model=ExitToken)
def issue_exit_token(invoice_id: str, service: InvoiceDependency) -> ExitToken:
    return ExitTokenService(service.repository).issue(invoice_id)


@router.post("/exit-tokens/consume")
def consume_exit_token(
    payload: ConsumeExitTokenRequest, request: Request, service: InvoiceDependency
) -> dict:
    key = os.getenv("BARRIER_INTEGRATION_KEY", "")
    supplied = request.headers.get("X-Barrier-Key", "")
    if not key or not hmac.compare_digest(key.encode(), supplied.encode()):
        raise PaymentError(
            "BARRIER_AUTH_REQUIRED", "Barrier integration key required", 403
        )
    return ExitTokenService(service.repository).consume(payload.token)
