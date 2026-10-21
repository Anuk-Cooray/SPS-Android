// hardware_integration_simulator_modal.dart
// Smart Parking (J26-IT-335) — Collaborating Subsystems Integration Simulator Modal
// Interactive testing for CCTV Vision (Samudi), IoT Barrier Gate (Varunprasath), and Smart Payment (Rathnayake)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';

class HardwareIntegrationSimulatorModal extends StatefulWidget {
  const HardwareIntegrationSimulatorModal({super.key});

  static Future<void> show(BuildContext context) {
    if (!AppConfig.kDemoMode) return Future.value();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HardwareIntegrationSimulatorModal(),
    );
  }

  @override
  State<HardwareIntegrationSimulatorModal> createState() =>
      _HardwareIntegrationSimulatorModalState();
}

class _HardwareIntegrationSimulatorModalState
    extends State<HardwareIntegrationSimulatorModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _lastResultTitle;
  String? _lastResultMessage;
  bool _isSuccessResult = true;

  // CCTV State
  String _selectedLotId = 'lot-colombo-01';
  String _selectedSlotId = 'A-01';
  double _cctvConfidence = 0.95;

  // Barrier State
  String _barrierId = 'barrier-gate-entry-01';
  final String _customQrToken = '';

  // Payment State
  final String _paymentMethod = 'card';
  String _lastPaymentRef = '';
  int _lastAmountPaid = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showResult({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    setState(() {
      _lastResultTitle = title;
      _lastResultMessage = message;
      _isSuccessResult = isSuccess;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final activeBooking = state.currentActiveBooking;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: Column(
        children: [
          // Drag handle & Header
          const SizedBox(height: AppSpace.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hardware Integration Stubs', style: AppText.h2.copyWith(color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      'Live HTTPS Contract Simulator · J26-IT-335',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            indicatorColor: c.accent,
            labelColor: c.accent,
            unselectedLabelColor: c.textSecondary,
            tabs: const [
              Tab(text: 'CCTV Vision'),
              Tab(text: 'IoT Barrier Gate'),
              Tab(text: 'Smart Payment'),
            ],
          ),

          // Tab Views
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: c.accent))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCctvTab(context, state, activeBooking),
                      _buildBarrierTab(context, state, activeBooking),
                      _buildPaymentTab(context, state, activeBooking),
                    ],
                  ),
          ),

          // Result feedback box
          if (_lastResultMessage != null) _buildResultBanner(context),
        ],
      ),
    );
  }

  // --- TAB 1: CCTV VISION SIMULATOR ---
  Widget _buildCctvTab(BuildContext context, ParkingStateManager state, Booking? activeBooking) {
    final c = context.colors;
    final currentLotId = activeBooking?.lotId ?? _selectedLotId;
    final currentSlotId = activeBooking?.slotId ?? _selectedSlotId;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        _buildInfoBox(
          context,
          'Teammate: Samudi · Occupancy Detection Model\n'
          'Endpoint: POST /ingestOccupancy (X-Camera-Api-Key)\n'
          'Rules: 30s stability debounce, confidence >= 0.70, conflict re-allocation.',
        ),
        const SizedBox(height: AppSpace.md),

        // Controls
        Text('Simulation Parameters', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: currentLotId,
                decoration: const InputDecoration(labelText: 'Target Lot ID'),
                onChanged: (val) => _selectedLotId = val,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: TextFormField(
                initialValue: currentSlotId,
                decoration: const InputDecoration(labelText: 'Target Bay ID'),
                onChanged: (val) => _selectedSlotId = val,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Vision Confidence: ${(_cctvConfidence * 100).toInt()}%',
                style: AppText.caption.copyWith(color: c.textSecondary)),
            if (_cctvConfidence < 0.70)
              Text('REJECT (< 0.70)', style: AppText.caption.copyWith(color: c.danger)),
          ],
        ),
        Slider(
          value: _cctvConfidence,
          min: 0.50,
          max: 1.00,
          divisions: 10,
          activeColor: _cctvConfidence >= 0.70 ? c.accent : c.danger,
          onChanged: (val) => setState(() => _cctvConfidence = val),
        ),

        const SizedBox(height: AppSpace.lg),
        Text('Action Presets', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.sm),

        // 1. Initial Reading (t=0s)
        ElevatedButton(
          onPressed: () => _executeCctvReading(
            lotId: currentLotId,
            slotId: currentSlotId,
            occupied: true,
            timestamp: DateTime.now(),
            actionDesc: 'Vehicle pull-in (t=0s debounce pending)',
          ),
          child: const Text('1. Send Initial Reading (t=0s, Pending Debounce)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 2. Commit Reading (t=35s)
        OutlinedButton(
          onPressed: () => _executeCctvReading(
            lotId: currentLotId,
            slotId: currentSlotId,
            occupied: true,
            timestamp: DateTime.now().add(const Duration(seconds: 35)),
            actionDesc: 'Stable occupancy committed (t=35s)',
          ),
          child: const Text('2. Confirm Reading (t=35s, State Committed)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 3. Inject Conflict
        OutlinedButton(
          onPressed: () => _executeCctvReading(
            lotId: currentLotId,
            slotId: currentSlotId,
            occupied: true,
            violation: true,
            timestamp: DateTime.now(),
            actionDesc: 'Unauthorized bay conflict -> Re-allocation triggered',
          ),
          style: OutlinedButton.styleFrom(foregroundColor: c.danger),
          child: const Text('3. Inject Conflict (Unauthorized Bay Intrusion)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 4. Vacated without payment
        OutlinedButton(
          onPressed: () => _executeCctvReading(
            lotId: currentLotId,
            slotId: currentSlotId,
            occupied: false,
            timestamp: DateTime.now(),
            actionDesc: 'Bay empty on active checked-in booking',
          ),
          style: OutlinedButton.styleFrom(foregroundColor: c.warning),
          child: const Text('4. Departure Without Payment Alert'),
        ),
      ],
    );
  }

  // --- TAB 2: IOT BARRIER GATE SIMULATOR ---
  Widget _buildBarrierTab(BuildContext context, ParkingStateManager state, Booking? activeBooking) {
    final c = context.colors;
    final token = activeBooking?.qrToken ?? _customQrToken;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        _buildInfoBox(
          context,
          'Teammate: Varunprasath · IoT Barrier Gate Access Control\n'
          'Endpoint: POST /validateQr (X-Device-Api-Key)\n'
          'Rules: Cryptographic HMAC signature, time-windowed, geofenced, single-use.',
        ),
        const SizedBox(height: AppSpace.md),

        Text('Barrier Hardware Device', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.sm),
        DropdownButtonFormField<String>(
          initialValue: _barrierId,
          decoration: const InputDecoration(labelText: 'Device Selector'),
          items: const [
            DropdownMenuItem(value: 'barrier-gate-entry-01', child: Text('Entry Gate 01 (General Lot Entry)')),
            DropdownMenuItem(value: 'barrier-gate-a03-geofenced', child: Text('Dedicated Barrier: Bay A-03 Only')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _barrierId = val);
          },
        ),
        const SizedBox(height: AppSpace.md),

        Text('Active Driver HMAC QR Token', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.cardSm),
            border: Border.all(color: c.border),
          ),
          child: SelectableText(
            token.isEmpty ? 'No active reservation token found. Reserve a slot first.' : token,
            style: AppText.caption.copyWith(fontFamily: 'monospace', color: c.textPrimary),
          ),
        ),

        const SizedBox(height: AppSpace.lg),
        Text('Barrier Test Presets', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.sm),

        // 1. Valid Check-in
        ElevatedButton(
          onPressed: token.isEmpty
              ? null
              : () => _executeBarrierValidation(
                    qrToken: token,
                    barrierId: 'barrier-gate-entry-01',
                    actionDesc: 'Valid HMAC Entry Check-In',
                  ),
          child: const Text('1. Scan Valid Token at Main Gate (Allow & Check-In)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 2. Wrong Slot Geofencing
        OutlinedButton(
          onPressed: token.isEmpty
              ? null
              : () => _executeBarrierValidation(
                    qrToken: token,
                    barrierId: 'barrier-gate-a03-geofenced',
                    actionDesc: 'Geofencing check: Wrong barrier presented',
                  ),
          style: OutlinedButton.styleFrom(foregroundColor: c.warning),
          child: const Text('2. Scan at Wrong Bay Barrier (Test WRONG_SLOT)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 3. Tampered Token
        OutlinedButton(
          onPressed: token.isEmpty
              ? null
              : () => _executeBarrierValidation(
                    qrToken: '${token.substring(0, token.length - 10)}0000000000',
                    barrierId: 'barrier-gate-entry-01',
                    actionDesc: 'Tampered cryptographic signature',
                  ),
          style: OutlinedButton.styleFrom(foregroundColor: c.danger),
          child: const Text('3. Scan Tampered Token (Test INVALID_SIGNATURE)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 4. Replay Attack
        OutlinedButton(
          onPressed: token.isEmpty
              ? null
              : () => _executeBarrierValidation(
                    qrToken: token,
                    barrierId: 'barrier-gate-entry-01',
                    actionDesc: 'Replaying already used token',
                  ),
          child: const Text('4. Replay Scan (Test TOKEN_ALREADY_USED)'),
        ),
      ],
    );
  }

  // --- TAB 3: SMART PAYMENT SIMULATOR ---
  Widget _buildPaymentTab(BuildContext context, ParkingStateManager state, Booking? activeBooking) {
    final c = context.colors;
    final bookingId = activeBooking?.id ?? '';
    final fee = activeBooking?.finalFee != null && activeBooking!.finalFee > 0
        ? activeBooking.finalFee
        : 300;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [
        _buildInfoBox(
          context,
          'Teammate: Rathnayake · Smart Payment & Settlement\n'
          'Endpoint: POST /paymentCompleted (X-Service-Api-Key)\n'
          'Rules: Idempotent on paymentRef, exit fee rounded up to billing block, frees bay.',
        ),
        const SizedBox(height: AppSpace.md),

        Text('Billing Summary', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.cardSm),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Booking ID:', style: AppText.caption.copyWith(color: c.textSecondary)),
                  Text(bookingId.isEmpty ? 'None active' : bookingId,
                      style: AppText.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Status:', style: AppText.caption.copyWith(color: c.textSecondary)),
                  Text(activeBooking?.status.displayName ?? 'N/A',
                      style: AppText.caption.copyWith(color: c.accent)),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Computed Total:', style: AppText.caption.copyWith(color: c.textSecondary)),
                  Text('LKR $fee',
                      style: AppText.body.copyWith(color: c.textPrimary, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpace.lg),
        Text('Settlement Actions', style: AppText.label.copyWith(color: c.textPrimary)),
        const SizedBox(height: AppSpace.sm),

        // 1. Settle Full Payment
        ElevatedButton(
          onPressed: bookingId.isEmpty
              ? null
              : () {
                  final ref = 'PAY-${DateTime.now().millisecondsSinceEpoch}';
                  _lastPaymentRef = ref;
                  _lastAmountPaid = fee;
                  _executePayment(
                    bookingId: bookingId,
                    paymentRef: ref,
                    amountPaid: fee,
                    actionDesc: 'Full payment settlement',
                  );
                },
          child: Text('1. Settle Full Payment (LKR $fee) & Free Bay'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 2. Idempotency Replay
        OutlinedButton(
          onPressed: _lastPaymentRef.isEmpty
              ? null
              : () => _executePayment(
                    bookingId: bookingId,
                    paymentRef: _lastPaymentRef,
                    amountPaid: _lastAmountPaid,
                    actionDesc: 'Idempotent replay with identical paymentRef',
                  ),
          child: Text('2. Test Idempotency Replay ($_lastPaymentRef)'),
        ),
        const SizedBox(height: AppSpace.sm),

        // 3. Underpayment
        OutlinedButton(
          onPressed: bookingId.isEmpty
              ? null
              : () {
                  final ref = 'PAY-LOW-${DateTime.now().millisecondsSinceEpoch}';
                  _executePayment(
                    bookingId: bookingId,
                    paymentRef: ref,
                    amountPaid: 50, // Less than fee
                    actionDesc: 'Underpayment test',
                  );
                },
          style: OutlinedButton.styleFrom(foregroundColor: c.danger),
          child: const Text('3. Underpayment Test (LKR 50 vs Full Fee)'),
        ),
      ],
    );
  }

  // --- LOGIC EXECUTION HANDLERS ---

  Future<void> _executeCctvReading({
    required String lotId,
    required String slotId,
    required bool occupied,
    DateTime? timestamp,
    bool? violation,
    required String actionDesc,
  }) async {
    setState(() => _isLoading = true);
    final state = context.read<ParkingStateManager>();
    try {
      final res = await state.simulateCctvReading(
        lotId: lotId,
        slotId: slotId,
        occupied: occupied,
        confidence: _cctvConfidence,
        timestamp: timestamp,
        violation: violation,
      );
      _showResult(
        title: 'CCTV Vision: $actionDesc',
        message: 'Status: ${res['state'] ?? 'ok'}\n'
            'Debounce: ${res['debounceStatus'] ?? 'none'}\n'
            'Conflict: ${res['conflictDetected'] ?? false}\n'
            'Reallocated: ${res['reallocatedToSlotId'] ?? 'no'}\n'
            '${res['message'] ?? ''}',
        isSuccess: true,
      );
    } catch (e) {
      _showResult(
        title: 'CCTV Error: $actionDesc',
        message: e.toString(),
        isSuccess: false,
      );
    }
  }

  Future<void> _executeBarrierValidation({
    required String qrToken,
    required String barrierId,
    required String actionDesc,
  }) async {
    setState(() => _isLoading = true);
    final state = context.read<ParkingStateManager>();
    try {
      final res = await state.simulateBarrierValidation(
        qrToken: qrToken,
        barrierId: barrierId,
      );
      final allow = res['allow'] == true;
      _showResult(
        title: 'Barrier Gate: $actionDesc',
        message: 'Access Allowed: $allow\n'
            'Code: ${res['code'] ?? 'OK'}\n'
            'Slot: ${res['slotId'] ?? 'N/A'}\n'
            '${res['reason'] ?? res['message'] ?? ''}',
        isSuccess: allow,
      );
    } catch (e) {
      _showResult(
        title: 'Barrier Gate Error: $actionDesc',
        message: e.toString(),
        isSuccess: false,
      );
    }
  }

  Future<void> _executePayment({
    required String bookingId,
    required String paymentRef,
    required int amountPaid,
    required String actionDesc,
  }) async {
    setState(() => _isLoading = true);
    final state = context.read<ParkingStateManager>();
    try {
      final res = await state.simulatePaymentSettlement(
        bookingId: bookingId,
        paymentRef: paymentRef,
        amountPaid: amountPaid,
        paymentMethod: _paymentMethod,
      );
      final isReplay = res['isIdempotentReplay'] == true;
      _showResult(
        title: 'Payment: $actionDesc',
        message: 'Status: ${res['status'] ?? 'completed'}\n'
            'Receipt: ${res['receiptNo'] ?? 'REC-001'}\n'
            'Bay Freed: ${res['slotFreed'] ?? 'yes'}\n'
            'Idempotent Replay: $isReplay',
        isSuccess: true,
      );
    } catch (e) {
      _showResult(
        title: 'Payment Error: $actionDesc',
        message: e.toString(),
        isSuccess: false,
      );
    }
  }

  Widget _buildInfoBox(BuildContext context, String text) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.cardSm),
        border: Border.all(color: c.divider),
      ),
      child: Text(text, style: AppText.caption.copyWith(color: c.textSecondary, height: 1.4)),
    );
  }

  Widget _buildResultBanner(BuildContext context) {
    final c = context.colors;
    final bg = _isSuccessResult ? c.accentSoft : c.danger.withValues(alpha: 0.15);
    final fg = _isSuccessResult ? c.accent : c.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: fg.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isSuccessResult ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 16, color: fg),
              const SizedBox(width: AppSpace.xs),
              Text(_lastResultTitle ?? 'Result',
                  style: AppText.body.copyWith(color: fg, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(_lastResultMessage ?? '', style: AppText.caption.copyWith(color: c.textPrimary)),
        ],
      ),
    );
  }
}
