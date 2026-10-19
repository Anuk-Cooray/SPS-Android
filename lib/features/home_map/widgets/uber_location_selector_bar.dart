// uber_location_selector_bar.dart
// Uber-style dual pickup/destination selector bar with swap capability

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/colombo_landmark_model.dart';
import 'colombo_search_modal.dart';

class UberLocationSelectorBar extends StatelessWidget {
  final ColomboLandmark pickup;
  final ColomboLandmark destination;
  final ValueChanged<ColomboLandmark> onPickupChanged;
  final ValueChanged<ColomboLandmark> onDestinationChanged;
  final VoidCallback onSwap;
  final VoidCallback onFilterTap;

  const UberLocationSelectorBar({
    super.key,
    required this.pickup,
    required this.destination,
    required this.onPickupChanged,
    required this.onDestinationChanged,
    required this.onSwap,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final distKm = destination.distanceToKm(pickup.latitude, pickup.longitude);
    final estMins = destination.estimatedDriveMinutes(pickup.latitude, pickup.longitude);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                // Visual Indicator Line (Green dot -> dashed line -> Black square)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981), // Uber green
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 1.5,
                      height: 24,
                      color: c.border,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // Text Fields (Pickup & Destination)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pickup Location
                      InkWell(
                        onTap: () async {
                          final selected = await ColomboSearchModal.show(
                            context,
                            isSelectingPickup: true,
                            currentOriginLat: pickup.latitude,
                            currentOriginLng: pickup.longitude,
                          );
                          if (selected != null) {
                            onPickupChanged(selected);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'START / PICKUP',
                                style: AppText.caption.copyWith(
                                  color: const Color(0xFF10B981),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                pickup.id == destination.id
                                    ? 'My Current Location'
                                    : pickup.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body.copyWith(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Divider(height: 8, thickness: 0.8),

                      // Destination Location
                      InkWell(
                        onTap: () async {
                          final selected = await ColomboSearchModal.show(
                            context,
                            isSelectingPickup: false,
                            currentOriginLat: pickup.latitude,
                            currentOriginLng: pickup.longitude,
                          );
                          if (selected != null) {
                            onDestinationChanged(selected);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PARKING DESTINATION',
                                style: AppText.caption.copyWith(
                                  color: c.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                destination.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body.copyWith(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Swap Button & Filter
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.swap_vert_rounded, color: c.textPrimary, size: 22),
                      tooltip: 'Swap Pickup & Destination',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: onSwap,
                    ),
                    IconButton(
                      icon: Icon(Icons.tune_rounded, color: c.textSecondary, size: 20),
                      tooltip: 'Scoring Filters',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: onFilterTap,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Route Telemetry Summary Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.route_rounded, size: 15, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  '$distKm km',
                  style: AppText.caption.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text('•', style: TextStyle(color: c.textSecondary)),
                const SizedBox(width: 8),
                Icon(Icons.schedule_rounded, size: 14, color: c.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$estMins mins',
                  style: AppText.caption.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: destination.congestionLevel == 'Extreme' ||
                            destination.congestionLevel == 'Very High'
                        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${destination.congestionLevel} Traffic',
                    style: AppText.caption.copyWith(
                      color: destination.congestionLevel == 'Extreme' ||
                              destination.congestionLevel == 'Very High'
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFD97706),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
