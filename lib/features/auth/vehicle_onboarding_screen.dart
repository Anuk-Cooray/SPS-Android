import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/parking_state_manager.dart';

class VehicleOnboardingScreen extends StatefulWidget {
  final VoidCallback onOnboardingComplete;

  const VehicleOnboardingScreen({
    super.key,
    required this.onOnboardingComplete,
  });

  @override
  State<VehicleOnboardingScreen> createState() => _VehicleOnboardingScreenState();
}

class _VehicleOnboardingScreenState extends State<VehicleOnboardingScreen> {
  final _plateController = TextEditingController(text: 'CAB-4821');
  VehicleType _selectedType = VehicleType.sedan;
  VehicleSize _selectedSize = VehicleSize.medium;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    final plate = _plateController.text.trim().toUpperCase();

    if (plate.isEmpty) {
      setState(() => _errorMessage = 'Please enter your license plate number');
      return;
    }

    if (plate.length < 4) {
      setState(() => _errorMessage = 'Plate number must be at least 4 characters');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final vehicle = Vehicle(
      id: 'veh-${DateTime.now().millisecondsSinceEpoch}',
      plateNumber: plate,
      type: _selectedType,
      size: _selectedSize,
      isDefault: true,
    );

    await context.read<ParkingStateManager>().completeVehicleOnboarding(vehicle);

    if (mounted) {
      widget.onOnboardingComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.xl),

              // Step indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_filled_rounded, size: 14, color: c.accent),
                    const SizedBox(width: 6),
                    Text(
                      'STEP 2 OF 2 · VEHICLE ONBOARDING',
                      style: AppText.overline.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Title
              Text(
                'Register your vehicle',
                style: AppText.h1.copyWith(color: c.textPrimary),
              ),

              const SizedBox(height: AppSpace.xs),

              // Subtitle
              Text(
                'Our dynamic slot re-optimization engine requires your vehicle size to guarantee size-compatible bay allocation.',
                style: AppText.body.copyWith(color: c.textSecondary),
              ),

              const SizedBox(height: AppSpace.xl),

              // License plate field
              Text(
                'License Plate Number',
                style: AppText.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.xs),
              TextField(
                controller: _plateController,
                textCapitalization: TextCapitalization.characters,
                style: AppText.title.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.badge_outlined,
                    color: c.textSecondary,
                    size: 20,
                  ),
                  hintText: 'e.g. CAB-4821 or WP-KA-1123',
                  errorText: _errorMessage,
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),

              const SizedBox(height: AppSpace.lg),

              // Vehicle Type Selection
              Text(
                'Vehicle Classification',
                style: AppText.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.sm),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: VehicleType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return ChoiceChip(
                    label: Text(type.displayName),
                    selected: isSelected,
                    selectedColor: c.primary,
                    backgroundColor: c.surface,
                    labelStyle: AppText.label.copyWith(
                      color: isSelected ? c.onPrimary : c.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? c.primary : c.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedType = type;
                          // Auto-suggest size based on type
                          if (type == VehicleType.motorbike || type == VehicleType.threeWheeler) {
                            _selectedSize = VehicleSize.small;
                          } else if (type == VehicleType.suv || type == VehicleType.van || type == VehicleType.lorry) {
                            _selectedSize = VehicleSize.large;
                          } else {
                            _selectedSize = VehicleSize.medium;
                          }
                        });
                      }
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: AppSpace.lg),

              // Vehicle Size Cards
              Text(
                'Size Profile (Optimization Constraint)',
                style: AppText.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.sm),

              ...VehicleSize.values.map((size) {
                final isSelected = _selectedSize == size;
                String description;
                IconData icon;

                switch (size) {
                  case VehicleSize.small:
                    description = 'Motorbikes & mini vehicles · Compact bays';
                    icon = Icons.two_wheeler_rounded;
                    break;
                  case VehicleSize.medium:
                    description = 'Sedans & hatchbacks · Standard bays (Rows A, B)';
                    icon = Icons.directions_car_rounded;
                    break;
                  case VehicleSize.large:
                    description = 'SUVs, vans & commercial · Designated wide bays (Rows C, D)';
                    icon = Icons.airport_shuttle_rounded;
                    break;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: InkWell(
                    onTap: () => setState(() => _selectedSize = size),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: isSelected ? c.accent : c.border,
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected ? c.accentSoft : c.surfaceMuted,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected ? c.accent : c.textSecondary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  size.displayName,
                                  style: AppText.title.copyWith(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: AppText.caption.copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: AppSpace.xl),

              // Submit Button
              PrimaryButton(
                text: 'Complete Setup & Start Parking',
                isLoading: _isLoading,
                onPressed: _handleSubmit,
              ),

              const SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
