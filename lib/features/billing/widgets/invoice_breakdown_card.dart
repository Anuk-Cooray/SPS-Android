import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/billing/fee_quote.dart';

class InvoiceBreakdownCard extends StatelessWidget {
  final FeeQuote quote;
  const InvoiceBreakdownCard({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          for (final item in quote.lineItems) ...[
            _row(context, item.label, item.amount),
            const SizedBox(height: AppSpace.sm),
          ],
          const Divider(),
          const SizedBox(height: AppSpace.sm),
          _row(context, 'Total', quote.total, bold: true),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    int amount, {
    bool bold = false,
  }) {
    final style = (bold ? AppText.title : AppText.body).copyWith(
      color: context.colors.textPrimary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: AppSpace.md),
        Text('LKR $amount', style: style),
      ],
    );
  }
}
