import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/data/services/billing/mock_billing_service.dart';
import 'package:smart_parking/features/billing/state/billing_state_manager.dart';

void main() {
  late BillingStateManager state;
  setUp(() => state = BillingStateManager(service: MockBillingService()));
  tearDown(() => state.dispose());

  Future<void> prepare({String lot = 'lot-main'}) => state.prepareQuote(
    bookingId: 'booking',
    entryTime: DateTime.utc(2026, 10, 19, 5),
    exitTime: DateTime.utc(2026, 10, 19, 6),
    lotId: lot,
  );

  test('guard selection waits; digital mock confirms invoice', () async {
    await prepare();
    await state.pay('guard');
    expect(state.invoice!.status, 'awaiting_guard');
    expect(state.isPaid, isFalse);
    await state.pay('stripe');
    expect(state.isPaid, isTrue);
    expect(state.session!.isMock, isTrue);
    await state.pay('guard');
    expect(state.isPaid, isTrue);
  });

  test('new quote clears prior confirmation', () async {
    await prepare();
    await state.pay('payhere');
    await prepare();
    expect(state.isPaid, isFalse);
    expect(state.invoice, isNull);
    expect(state.session, isNull);
  });

  test('errors are exposed and busy is reset', () async {
    await state.pay('stripe');
    expect(state.error, isNotNull);
    expect(state.isBusy, isFalse);
    await prepare();
    expect(state.error, isNull);
    await state.pay('unsupported');
    expect(state.error, isNotNull);
    expect(state.isPaid, isFalse);
    await prepare(lot: 'missing');
    expect(state.quote, isNull);
    expect(state.error, isNotNull);
  });

  test('listeners observe busy and completed states', () async {
    final busyStates = <bool>[];
    state.addListener(() => busyStates.add(state.isBusy));
    await prepare();
    expect(busyStates, [true, false]);
  });
}
