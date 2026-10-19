# Immutable billing data

## Approach and alternatives
JSON models hold quotes, invoice items, invoices, payment sessions, forecast points and short-lived exit passes. Payment sessions retain the mock confirmation token and integer minor-unit amount needed for the DEBUG callback. Amounts use integer LKR; times normalize to UTC. Quote lists are copied and made unmodifiable. Plain serializers avoid code generation dependencies.

## Limitations
Parsing assumes correctly typed API responses. Status strings follow the upcoming API.

## Viva questions
- Why integer money? It avoids binary floating-point errors.
- Why UTC? It preserves instants across devices.
- Why copy lists? Final references alone do not prevent list mutation.
