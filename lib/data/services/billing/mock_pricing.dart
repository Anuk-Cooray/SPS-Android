import '../../models/billing/fee_quote.dart';
import '../../models/billing/invoice_line_item.dart';

/// Mirrors provisional backend rules using integer fractions, never double money.
/// Colombo has no daylight-saving changes; shifted UTC fields represent wall time.
const colomboOffset = Duration(hours: 5, minutes: 30);

DateTime colomboTime(DateTime value) => value.toUtc().add(colomboOffset);

int mockDemandPermille(DateTime timestamp) {
  final local = colomboTime(timestamp);
  return local.weekday <= 5 && (local.hour == 8 || local.hour == 13)
      ? 800
      : 300;
}

int _overlap(DateTime start, DateTime end, DateTime left, DateTime right) {
  final from = start.isAfter(left) ? start : left;
  final to = end.isBefore(right) ? end : right;
  return to.isAfter(from) ? to.difference(from).inMicroseconds : 0;
}

int _round(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

FeeQuote mockQuote({
  required String bookingId,
  required DateTime entryTime,
  required DateTime exitTime,
  required int rate,
  int extensionMinutes = 0,
  int arrivalExtensionFee = 0,
  String? upgradeFromSlotId,
  String? upgradeToSlotId,
}) {
  final start = colomboTime(entryTime);
  final end = colomboTime(exitTime);
  final duration = end.difference(start).inMicroseconds;
  if (duration <= 0 ||
      extensionMinutes < 0 ||
      arrivalExtensionFee < 0 ||
      extensionMinutes * Duration.microsecondsPerMinute > duration) {
    throw ArgumentError(
      'Exit must follow entry; overtime must fit the stay; fees cannot be negative',
    );
  }
  if ((upgradeFromSlotId == null) != (upgradeToSlotId == null)) {
    throw ArgumentError('Provide both upgrade slot IDs');
  }
  final items = <InvoiceLineItem>[];
  var subtotal = 0;
  var total = 0;
  // Common denominator covers base rate /60, peak premium /240 and overtime /120.
  const scale = 240 * Duration.microsecondsPerMinute;
  final boost = (mockDemandPermille(exitTime) - 600).clamp(0, 300).toInt();
  if (duration <= 10 * Duration.microsecondsPerMinute) {
    items.add(
      const InvoiceLineItem(
        label: 'Grace period',
        qty: 1,
        unit: 'stay',
        amount: 0,
      ),
    );
    subtotal = arrivalExtensionFee;
    total = arrivalExtensionFee.clamp(0, 1200).toInt();
    if (arrivalExtensionFee > 0) {
      items.add(
        InvoiceLineItem(
          label: 'Arrival deadline extension',
          qty: 1,
          unit: 'booked fee',
          amount: arrivalExtensionFee,
        ),
      );
    }
    if (total != subtotal) {
      items.add(
        InvoiceLineItem(
          label: 'Daily cap adjustment',
          qty: 1,
          unit: 'adjustment',
          amount: total - subtotal,
        ),
      );
    }
  } else {
    var cursor = start;
    while (cursor.isBefore(end)) {
      final midnight = DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
      final dayEnd = end.isBefore(midnight) ? end : midnight;
      final actual = dayEnd.difference(cursor).inMicroseconds;
      const block = 15 * Duration.microsecondsPerMinute;
      final blocks = (actual + block - 1) ~/ block;
      final base = blocks * 15 * rate * scale ~/ 60;
      var peak = 0;
      if (cursor.weekday <= 5) {
        for (final hours in [
          [7, 30, 9, 30],
          [15, 30, 17, 30],
        ]) {
          peak +=
              _overlap(
                cursor,
                dayEnd,
                DateTime.utc(
                  cursor.year,
                  cursor.month,
                  cursor.day,
                  hours[0],
                  hours[1],
                ),
                DateTime.utc(
                  cursor.year,
                  cursor.month,
                  cursor.day,
                  hours[2],
                  hours[3],
                ),
              ) *
              rate;
        }
      }
      final overtime =
          _overlap(
            cursor,
            dayEnd,
            end.subtract(Duration(minutes: extensionMinutes)),
            end,
          ) *
          rate *
          2;
      final arrival = cursor == start ? arrivalExtensionFee : 0;
      final raw = base + peak + overtime;
      final daySubtotal =
          _round(base, scale) +
          _round(peak, scale) +
          _round(overtime, scale) +
          arrival;
      final numerator = raw * (600 + boost) + arrival * scale * 600;
      final denominator = scale * 600;
      final dayTotal = _round(
        numerator.clamp(0, 1200 * denominator).toInt(),
        denominator,
      );
      final date = cursor.toIso8601String().substring(0, 10);
      items.add(
        InvoiceLineItem(
          label: '$date Parking',
          qty: blocks,
          unit: '15-minute block',
          amount: _round(base, scale),
        ),
      );
      if (peak > 0) {
        items.add(
          InvoiceLineItem(
            label: '$date Peak premium',
            qty: 1,
            unit: 'overlap',
            amount: _round(peak, scale),
          ),
        );
      }
      if (overtime > 0) {
        items.add(
          InvoiceLineItem(
            label: '$date Overtime premium',
            qty: 1,
            unit: 'overlap',
            amount: _round(overtime, scale),
          ),
        );
      }
      if (arrival > 0) {
        items.add(
          InvoiceLineItem(
            label: 'Arrival deadline extension',
            qty: 1,
            unit: 'booked fee',
            amount: arrival,
          ),
        );
      }
      if (dayTotal != daySubtotal) {
        items.add(
          InvoiceLineItem(
            label: '$date Surge / daily cap / rounding',
            qty: 1,
            unit: 'adjustment',
            amount: dayTotal - daySubtotal,
          ),
        );
      }
      subtotal += daySubtotal;
      total += dayTotal;
      cursor = dayEnd;
    }
  }
  if (upgradeFromSlotId != null) {
    items.add(
      InvoiceLineItem(
        label: 'Upgrade $upgradeFromSlotId → $upgradeToSlotId',
        qty: 1,
        unit: 'upgrade',
        amount: 0,
      ),
    );
  }
  return FeeQuote(
    bookingId: bookingId,
    entryTime: entryTime,
    exitTime: exitTime,
    lineItems: items,
    subtotal: subtotal,
    surgeAmount: total - subtotal,
    total: total,
    explanation:
        'Offline synthetic demo: 10-minute stay grace, 15-minute blocks per Colombo day; '
        'peak premiums apply to actual overlap. Overtime is within the stay. '
        'Exit-hour demand ${mockDemandPermille(exitTime) / 1000} sets surge; daily cap LKR 1200. '
        'Booked arrival fees apply once without surge, within the entry-day cap. '
        'No upgrade rate delta is recorded, so a slot change is free.',
  );
}
