# FastAPI scaffold and quote boundary

## What it does
`backend/app/main.py` exposes health and generated API docs. `schemas/billing.py` validates request timestamps/demand and describes integer-LKR responses. `api/billing_routes.py` looks up trusted lot rates from `core/config.py`, invokes the pure engine and normalizes response timestamps to UTC. Error handlers return a common code/message envelope for validation and HTTP errors.

## Why this approach / alternatives
FastAPI and Pydantic provide readable typed request/response schemas and an interactive demo. Keeping routes separate from pricing allows tests without a server. The registry mirrors existing Flutter mock data; a client cannot set its own hourly price. Node.js would duplicate the planned Python forecast integration and is deferred to the team's stack decision.

## Limitations
Health, quote, forecast, invoice and sandbox/mock payment routes are implemented through Step 6. Omitted demand uses the synthetic exit-hour forecast; missing models return 503. Upgrade IDs require a pair but there is no rate history to price them. An in-memory invoice repository exists; no auth, production payments or persistence yet. Environment examples contain blank keys only; payment config now reads backend/.env. Tests run on Python 3.13, while source targets Python 3.10+. Current Starlette emits an httpx TestClient deprecation warning; tests still pass.

## Three viva questions
- **Why require aware timestamps?** Naive values do not identify a reliable instant across devices/timezones.
- **Why look up rates on the server?** Client-supplied prices cannot be authoritative.
- **Why not return raw exceptions?** A stable error envelope lets Flutter show a predictable message without leaking internal details.
