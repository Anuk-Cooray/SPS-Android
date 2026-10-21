import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/parking_state_manager.dart';

class ProfileScreen extends StatelessWidget {
  final VoidCallback? onLogout;

  const ProfileScreen({super.key, this.onLogout});

  void _showAddVehicleDialog(BuildContext context) {
    final plateController = TextEditingController();
    VehicleType selectedType = VehicleType.sedan;
    VehicleSize selectedSize = VehicleSize.medium;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final c = context.colors;
          return Padding(
            padding: EdgeInsets.only(
              left: AppSpace.lg,
              right: AppSpace.lg,
              top: AppSpace.lg,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Vehicle', style: AppText.h2.copyWith(color: c.textPrimary)),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: plateController,
                  decoration: const InputDecoration(
                    labelText: 'License Plate (e.g. CAB-4821)',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<VehicleType>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Vehicle Type'),
                  items: VehicleType.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.displayName));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: AppSpace.md),
                DropdownButtonFormField<VehicleSize>(
                  initialValue: selectedSize,
                  decoration: const InputDecoration(labelText: 'Size'),
                  items: VehicleSize.values.map((s) {
                    return DropdownMenuItem(value: s, child: Text(s.displayName));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedSize = val);
                  },
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton(
                  onPressed: () {
                    final plate = plateController.text.trim();
                    if (plate.isNotEmpty) {
                      context.read<ParkingStateManager>().addVehicle(
                            Vehicle(
                              id: 'veh-${DateTime.now().millisecondsSinceEpoch}',
                              plateNumber: plate,
                              type: selectedType,
                              size: selectedSize,
                            ),
                          );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Save Vehicle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final user = state.currentUser;
    final prefs = user.preferences;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          children: [
            const SizedBox(height: AppSpace.lg),

            // Profile Header
            Row(
              children: [
                // Initials Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppEffects.hero,
                    shape: BoxShape.circle,
                    boxShadow: AppEffects.glow(c.accent, strength: 0.5, blur: 20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(user.name),
                    style: AppText.h2.copyWith(
                      color: c.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(width: AppSpace.md),

                // Name & Email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: AppText.title.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: AppText.body.copyWith(
                          color: c.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // Edit button
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(60, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Edit', style: AppText.label.copyWith(color: c.textPrimary)),
                ),
              ],
            ),

            const SizedBox(height: AppSpace.xl),

            // Vehicles Section
            Text(
              'VEHICLES',
              style: AppText.overline.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpace.xs),

            Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: c.border),
              ),
              child: Column(
                children: [
                  ...user.vehicles.map((veh) {
                    return ListTile(
                      leading: Icon(Icons.directions_car_rounded, color: c.textPrimary),
                      title: Text(
                        veh.plateNumber,
                        style: AppText.title.copyWith(color: c.textPrimary),
                      ),
                      subtitle: Text(
                        '${veh.type.displayName} · ${veh.size.displayName}',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                      trailing: veh.isDefault
                          ? Text(
                              'Default',
                              style: AppText.label.copyWith(
                                color: c.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : TextButton(
                              onPressed: () => state.setDefaultVehicle(veh.id),
                              child: const Text('Set default'),
                            ),
                    );
                  }),
                  const Divider(),
                  InkWell(
                    onTap: () => _showAddVehicleDialog(context),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: AppSpace.md,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add_rounded, color: c.textPrimary, size: 20),
                          const SizedBox(width: AppSpace.sm),
                          Text(
                            'Add vehicle',
                            style: AppText.title.copyWith(color: c.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpace.xl),

            // Parking Preferences Section
            Text(
              'PARKING PREFERENCES',
              style: AppText.overline.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpace.xs),

            Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: c.border),
              ),
              child: Column(
                children: [
                  // Switch 1: Better slot offers
                  SwitchListTile(
                    title: Text(
                      'Better slot offers',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    subtitle: Text(
                      'Suggest a closer slot before I arrive',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                    value: prefs.allowUpgradeOffers,
                    onChanged: (val) {
                      state.updatePreferences(prefs.copyWith(allowUpgradeOffers: val));
                    },
                  ),
                  const Divider(),

                  // Switch 2: Prefer near entrance
                  SwitchListTile(
                    title: Text(
                      'Prefer near entrance',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    subtitle: Text(
                      'Prioritizes bays closer to building entrances',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                    value: prefs.preferNearEntrance,
                    onChanged: (val) {
                      state.updatePreferences(prefs.copyWith(preferNearEntrance: val));
                    },
                  ),
                  const Divider(),

                  // Switch 3: Covered parking only
                  SwitchListTile(
                    title: Text(
                      'Covered parking only',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    subtitle: Text(
                      'Shade and rain cover',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                    value: prefs.coveredParkingOnly,
                    onChanged: (val) {
                      state.updatePreferences(prefs.copyWith(coveredParkingOnly: val));
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpace.xl),

            // Payment & Logout
            Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: c.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text('Payment methods', style: AppText.title.copyWith(color: c.textPrimary)),
                    trailing: Text(
                      user.defaultPaymentMethod ?? 'None saved',
                      style: AppText.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.analytics_outlined, color: c.textPrimary),
                    title: Text(
                      'Live Admin & Research Metrics',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
                    onTap: () => Navigator.pushNamed(context, '/admin'),
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(
                      'Log out',
                      style: AppText.title.copyWith(color: c.danger),
                    ),
                    onTap: () {
                      state.logout();
                      onLogout?.call();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpace.xxl),
          ],
        ),
      ),
    );
  }
}

/// Up to two initials from a display name, e.g. "Anuk Cooray" -> "AC", "DRIVER" -> "D".
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}
