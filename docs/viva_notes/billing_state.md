# Independent billing state

## Approach / alternatives
BillingStateManager is a ChangeNotifier injected with BillingService. It loads a quote from checkedInAt to now, forwards the booked arrival fee, and passes actual upgrade slot IDs. Missing check-in blocks payment. It keeps quote/invoice/session, busy/error state and a separately loaded synthetic forecast. The chart can fail without erasing a valid quote. MultiProvider keeps this state separate from parking state.

A new quote clears old confirmation. Once an invoice exists, reopening the same booking resumes its fixed invoice instead of silently repricing it. startPayment is followed by getInvoice; checkout existence never authorizes completion. Manual refresh allows a later webhook to confirm settlement. Paid settlement fetches an exit pass. The screen calls its completion callback once when the user taps Finish demo exit for its own paid booking with an unexpired pass.

## Limitations
No automatic polling. The HTTP service recovers invoice identity by booking from persistent local SQLite. Teammate booking state itself is not persisted by billing. Old forecast responses are ignored using a request counter. Disposal prevents late notifications and closes the owned HTTP client. The screen's initial load runs after its first frame so Provider is not mutated during build. Navigation fetches the latest parking booking because the earlier captured booking predates check-in. Teammate parking state itself is unchanged.

## Three viva questions
- **Who finalizes a parking booking?** The existing parent callback calls ParkingStateManager only after a paid invoice.
- **Why separate forecast loading?** An optional chart error should not remove an already valid fee quote.
- **Why resume an invoice?** Changing its price while a checkout is pending could mismatch the provider's recorded amount.
