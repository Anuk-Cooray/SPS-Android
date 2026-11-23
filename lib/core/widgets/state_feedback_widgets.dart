// state_feedback_widgets.dart
// Smart Parking (J26-IT-335) — Unified Empty, Error, and Offline State Feedback Widgets

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable empty state view with WCAG 44px compliant action targets
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 32, color: c.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              style: AppText.title.copyWith(color: c.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              description,
              style: AppText.body.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 44), // WCAG 44px minimum target
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable error feedback view with retry action
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorState({
    super.key,
    this.title = 'Unable to Load',
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: c.danger.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.error_outline_rounded, size: 28, color: c.danger),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              style: AppText.title.copyWith(color: c.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              message,
              style: AppText.body.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpace.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(120, 44), // WCAG 44px
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable non-intrusive offline connectivity banner
class AppOfflineBanner extends StatelessWidget {
  final bool isOffline;
  final VoidCallback? onReconnect;

  const AppOfflineBanner({
    super.key,
    required this.isOffline,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();
    final c = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 8),
      color: c.surfaceMuted,
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: c.textSecondary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              'Offline mode · Displaying cached data',
              style: AppText.caption.copyWith(color: c.textSecondary, fontSize: 12),
            ),
          ),
          if (onReconnect != null)
            InkWell(
              onTap: onReconnect,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Reconnect',
                  style: AppText.caption.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
