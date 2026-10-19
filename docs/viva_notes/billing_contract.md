# Billing service contract

## Approach / alternatives
Both legacy method signatures remain unchanged. Quote, invoice, payment-session, invoice-status and demand-forecast operations separate responsibilities. The UI depends on this interface; a factory selects the default offline mock or the HTTP adapter. Keeping it separate from ParkingStateManager follows the existing Provider structure without mixing billing and slot allocation.

## Arrival-fee clarification
Step 7 adds one optional `arrivalExtensionFee = 0` argument to quoteFee. Booking.extensionFee is an existing arrival-deadline charge, not a parking overtime duration. Passing the recorded integer fee explicitly preserves it without inventing minutes. The backend uses `arrival_extension_fee`; overtime stays in `extension_minutes`. Existing callers can omit the new argument, and the original calculateFee/processPayment signatures are intact.

## Limitations
Legacy calculateFee lacks lot/time information. The mock retains its documented main-lot default; HTTP requires an already issued quote and returns that authoritative total. Production must load booking charges on the server rather than trusting the demo client's recorded fee. New model imports are required alongside the contract block; teammate contracts remain unchanged.

## Three viva questions
- **Why preserve the old methods?** Existing callers must continue to compile.
- **Why separate sessions from invoices?** A checkout session initiates payment; the invoice records settlement.
- **Why add a separate arrival fee?** The booking records a money amount, not overtime minutes, and they have different tariff meanings.
