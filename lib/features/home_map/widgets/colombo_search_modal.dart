// colombo_search_modal.dart
// Interactive search and suggestion modal for Colombo landmarks & crowded locations

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/colombo_landmark_model.dart';
import '../../../data/services/colombo_location_service.dart';

class ColomboSearchModal extends StatefulWidget {
  final bool isSelectingPickup;
  final double currentOriginLat;
  final double currentOriginLng;
  final ValueChanged<ColomboLandmark> onLandmarkSelected;

  const ColomboSearchModal({
    super.key,
    required this.isSelectingPickup,
    required this.currentOriginLat,
    required this.currentOriginLng,
    required this.onLandmarkSelected,
  });

  static Future<ColomboLandmark?> show(
    BuildContext context, {
    required bool isSelectingPickup,
    required double currentOriginLat,
    required double currentOriginLng,
  }) {
    return showModalBottomSheet<ColomboLandmark>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ColomboSearchModal(
        isSelectingPickup: isSelectingPickup,
        currentOriginLat: currentOriginLat,
        currentOriginLng: currentOriginLng,
        onLandmarkSelected: (landmark) {
          Navigator.of(ctx).pop(landmark);
        },
      ),
    );
  }

  @override
  State<ColomboSearchModal> createState() => _ColomboSearchModalState();
}

class _ColomboSearchModalState extends State<ColomboSearchModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Crowded Hubs',
    'Shopping & Mall',
    'Transit & Market',
    'Tourism & Landmark',
    'Civic & Leisure',
    'University & Tech',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ColomboLandmark> _getFilteredLandmarks() {
    final query = _searchCtrl.text.trim();
    List<ColomboLandmark> list;
    if (query.isEmpty) {
      if (_selectedCategory == 'Crowded Hubs') {
        list = ColomboLocationService.getCrowdedPlaces();
      } else if (_selectedCategory != 'All') {
        list = ColomboLocationService.landmarks
            .where((l) => l.category == _selectedCategory)
            .toList();
      } else {
        list = ColomboLocationService.landmarks;
      }
    } else {
      list = ColomboLocationService.search(query);
      if (_selectedCategory == 'Crowded Hubs') {
        list = list.where((l) => l.isCrowded).toList();
      } else if (_selectedCategory != 'All') {
        list = list.where((l) => l.category == _selectedCategory).toList();
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = _getFilteredLandmarks();
    final title = widget.isSelectingPickup
        ? 'Select Pickup / Start Location'
        : 'Search Colombo Destination';

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Top Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Row(
              children: [
                Icon(
                  widget.isSelectingPickup
                      ? Icons.trip_origin_rounded
                      : Icons.location_on_rounded,
                  color: widget.isSelectingPickup ? c.accent : c.textPrimary,
                  size: 24,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: AppText.h2.copyWith(color: c.textPrimary, fontSize: 18),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: c.textSecondary, size: 20),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      style: AppText.body.copyWith(color: c.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search Galle Face, Pettah, MC, Lotus Tower...',
                        hintStyle: AppText.body.copyWith(color: c.textSecondary),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: Icon(Icons.cancel_rounded, color: c.textSecondary, size: 18),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          // Category Chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              itemCount: _categories.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                  labelStyle: AppText.caption.copyWith(
                    color: isSelected ? c.onPrimary : c.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  selectedColor: c.primary,
                  backgroundColor: c.surfaceMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? c.primary : c.border,
                    ),
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),

          const SizedBox(height: AppSpace.xs),
          const Divider(height: 1),

          // Results List
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, color: c.textSecondary, size: 40),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          'No Colombo locations found',
                          style: AppText.body.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    itemCount: results.length,
                    separatorBuilder: (_, i) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      final distKm = item.distanceToKm(
                        widget.currentOriginLat,
                        widget.currentOriginLng,
                      );
                      final estMins = item.estimatedDriveMinutes(
                        widget.currentOriginLat,
                        widget.currentOriginLng,
                      );

                      return InkWell(
                        onTap: () => widget.onLandmarkSelected(item),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category Icon Avatar
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: c.surfaceMuted,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: c.border),
                                ),
                                child: Icon(
                                  _getCategoryIcon(item.category),
                                  color: c.textPrimary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),

                              // Text Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: AppText.body.copyWith(
                                              color: c.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (item.isCrowded)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.danger.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Crowded',
                                              style: AppText.caption.copyWith(
                                                color: c.danger,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.address} · ${item.zone}',
                                      style: AppText.caption.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    // Metric badges
                                    Row(
                                      children: [
                                        Icon(Icons.directions_car_rounded, size: 14, color: c.accent),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$distKm km ($estMins mins)',
                                          style: AppText.caption.copyWith(
                                            color: c.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(Icons.local_parking_rounded, size: 14, color: c.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.primaryLotName,
                                          style: AppText.caption.copyWith(
                                            color: c.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Shopping & Mall':
        return Icons.shopping_bag_rounded;
      case 'Transit & Market':
        return Icons.directions_transit_rounded;
      case 'Promenade & Oceanfront':
        return Icons.beach_access_rounded;
      case 'Tourism & Landmark':
        return Icons.attractions_rounded;
      case 'Healthcare & Emergency':
        return Icons.local_hospital_rounded;
      case 'Conventions & Events':
        return Icons.meeting_room_rounded;
      case 'Civic & Leisure':
        return Icons.park_rounded;
      case 'University & Tech':
        return Icons.school_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }
}
