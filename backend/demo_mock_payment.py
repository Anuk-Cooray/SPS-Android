"""Exercise a running local API: quote → invoice → mock checkout → callback.

Start Uvicorn with DEBUG=true and leave payment credentials blank first.
No external payment gateway is contacted by this demo client.
"""

import argparse
from uuid import uuid4

import httpx


def run_demo(client: httpx.Client) -> dict:
    quote = client.post(
        "/api/v1/billing/quote",
        json={
            "booking_id": "BK-DEMO-" + uuid4().hex,
            "lot_id": "lot-main",
            "entry_time": "2026-10-19T10:00:00+05:30",
            "exit_time": "2026-10-19T11:00:00+05:30",
            "demand_level": "0.5",
        },
    )
    quote.raise_for_status()
    invoice = client.post(
        "/api/v1/billing/invoices",
        json={"booking_id": quote.json()["booking_id"], "quote": quote.json()},
    )
    invoice.raise_for_status()
    invoice_id = invoice.json()["id"]
    session_response = client.post(
        f"/api/v1/billing/invoices/{invoice_id}/pay", json={"method": "payhere"}
    )
    session_response.raise_for_status()
    session = session_response.json()
    if session["provider"] != "mock":
        raise RuntimeError(
            "Offline demo expects blank PayHere credentials and a mock session"
        )
    if (
        client.get(f"/api/v1/billing/invoices/{invoice_id}").json()["status"]
        != "pending"
    ):
        raise RuntimeError("Checkout must remain pending before the callback")
    body = {
        "invoice_id": invoice_id,
        "session_id": session["id"],
        "token": session["mock_webhook_token"],
        "status": "paid",
        "amount_minor": session["amount_minor"],
        "currency": session["currency"],
    }
    callback = client.post("/api/v1/billing/webhooks/mock", json=body)
    callback.raise_for_status()
    repeat = client.post("/api/v1/billing/webhooks/mock", json=body)
    repeat.raise_for_status()
    final = client.get(f"/api/v1/billing/invoices/{invoice_id}")
    final.raise_for_status()
    if final.json()["status"] != "paid" or repeat.json().get("duplicate") is not True:
        raise RuntimeError(
            "Expected paid settlement and an idempotent repeated callback"
        )
    return {
        "invoice_id": invoice_id,
        "total_lkr": quote.json()["total"],
        "status": final.json()["status"],
        "mock": True,
        "duplicate_callback": True,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    with httpx.Client(base_url=args.base_url, timeout=15) as client:
        print(run_demo(client))


if __name__ == "__main__":
    main()
