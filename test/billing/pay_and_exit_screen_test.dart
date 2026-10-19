import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/billing/payment_session.dart';
import 'package:smart_parking/data/models/billing/invoice.dart';
import 'package:smart_parking/data/services/billing/mock_billing_service.dart';
import 'package:smart_parking/features/billing/pay_and_exit_screen.dart';
import 'package:smart_parking/features/billing/state/billing_state_manager.dart';
import 'package:smart_parking/features/billing/widgets/demand_forecast_chart.dart';

Booking booking({bool checkedIn = true}) {
  final now = DateTime.now();
  return Booking(
    id: 'BK-SCREEN',
    userId: 'user',
    vehicleId: 'vehicle',
    vehiclePlate: 'TEST-001',
    lotId: 'lot-main',
    lotName: 'Main Building Lot',
    slotId: 'B-01',
    originalSlotId: 'A-06',
    bookedAt: now.subtract(const Duration(hours: 2)),
    arrivalTime: now.subtract(const Duration(hours: 1)),
    durationHours: 2,
    checkedInAt: checkedIn ? now.subtract(const Duration(minutes: 30)) : null,
    status: checkedIn ? BookingStatus.checkedIn : BookingStatus.reserved,
    estimatedFee: 200,
    extensionFee: 50,
    qrToken: 'entry-token',
  );
}

class PendingService extends MockBillingService {
  bool confirmed = false;
  @override
  Future<PaymentSession> startPayment({
    required String invoiceId,
    required String method,
  }) async => PaymentSession(
    id: 'pending',
    invoiceId: invoiceId,
    method: method,
    provider: 'stripe',
    status: 'pending',
    isMock: false,
  );
  @override
  Future<Invoice> getInvoice(String invoiceId) async {
    final invoice = await super.getInvoice(invoiceId);
    return confirmed ? invoice.withStatus('paid') : invoice;
  }
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(
    WidgetTester tester,
    BillingStateManager state,
    Booking visit,
    ValueChanged<int> onPaid,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light,
          home: PayAndExitScreen(booking: visit, onPaymentCompleted: onPaid),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quote rows include the booked arrival fee and upgrade; mock confirms once',
    (tester) async {
      final state = BillingStateManager(service: MockBillingService());
      addTearDown(state.dispose);
      final results = <int>[];
      await show(tester, state, booking(), results.add);
      expect(
        state.quote!.lineItems.any(
          (item) =>
              item.label == 'Arrival deadline extension' && item.amount == 50,
        ),
        isTrue,
      );
      expect(
        state.quote!.lineItems.any(
          (item) => item.label == 'Upgrade A-06 → B-01',
        ),
        isTrue,
      );
      expect(find.text('Parked 0 h 30 min'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Visa •••• 4821 · Sandbox'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Visa •••• 4821 · Sandbox'), findsOneWidget);
      await tester.tap(find.text('Pay LKR ${state.quote!.total}'));
      await tester.pumpAndSettle();
      expect(results, [state.invoice!.quote.total]);
      await tester.pump();
      expect(results, hasLength(1));
    },
  );

  testWidgets('booth selection stays unpaid and shows an invoice reference', (
    tester,
  ) async {
    final state = BillingStateManager(service: MockBillingService());
    addTearDown(state.dispose);
    final results = <int>[];
    await show(tester, state, booking(), results.add);
    await tester.scrollUntilVisible(
      find.text('Pay at booth (guard)').hitTestable(),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pay at booth (guard)'));
    await tester.pump();
    await tester.tap(find.text('Pay at booth'));
    await tester.pumpAndSettle();
    expect(state.invoice!.status, 'awaiting_guard');
    expect(results, isEmpty);
    expect(find.text('Check status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Invoice reference only · not an exit QR'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Invoice reference only · not an exit QR'),
      findsOneWidget,
    );
  });

  testWidgets(
    'pending checkout does not complete until invoice refresh confirms paid',
    (tester) async {
      final service = PendingService();
      final state = BillingStateManager(service: service);
      addTearDown(state.dispose);
      final results = <int>[];
      await show(tester, state, booking(), results.add);
      await tester.tap(find.text('Pay LKR ${state.quote!.total}'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.text('Check status'), findsOneWidget);
      service.confirmed = true;
      await tester.tap(find.text('Check status'));
      await tester.pumpAndSettle();
      expect(results, [state.invoice!.quote.total]);
    },
  );

  testWidgets('unchecked booking cannot start payment', (tester) async {
    final state = BillingStateManager(service: MockBillingService());
    addTearDown(state.dispose);
    await show(
      tester,
      state,
      booking(checkedIn: false),
      (_) => fail('Must not complete'),
    );
    expect(find.text('Check in before paying for parking.'), findsOneWidget);
    expect(state.quote, isNull);
  });

  testWidgets(
    'forecast paints a monochrome band in dark mode without overflow',
    (tester) async {
      final points = await MockBillingService().getDemandForecast(
        lotId: 'lot-main',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: DemandForecastChart(points: points),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic demand · Colombo time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
