import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/services/parking_state_manager.dart';
import '../reoptimization/engine/scoring_weights.dart';

class EngineTuningModal extends StatefulWidget {
  const EngineTuningModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EngineTuningModal(),
    );
  }

  @override
  State<EngineTuningModal> createState() => _EngineTuningModalState();
}

class _EngineTuningModalState extends State<EngineTuningModal> {
  late double _distWeight;
  late double _sizeWeight;
  late double _prefWeight;
  late double _demandWeight;
  late double _minImprovementMeters;
  late double _minScorePoints;
  late double _offerTimeoutSec;
  late double _triggerEtaMinutes;

  @override
  void initState() {
    super.initState();
    final weights = context.read<ParkingStateManager>().scoringWeights;
    _distWeight = weights.distanceWeight;
    _sizeWeight = weights.sizeFitWeight;
    _prefWeight = weights.preferenceWeight;
    _demandWeight = weights.demandWeight;
    _minImprovementMeters = weights.minImprovementMeters.toDouble();
    _minScorePoints = weights.minScoreImprovementPoints;
    _offerTimeoutSec = weights.offerTimeoutSeconds.toDouble();
    _triggerEtaMinutes = weights.upgradeTriggerEtaMinutes.toDouble();
  }

  double get _currentSum =>
      _distWeight + _sizeWeight + _prefWeight + _demandWeight;

  bool get _isValidSum => (_currentSum - 1.0).abs() <= 0.001;

  void _normalizeWeights() {
    final sum = _currentSum;
    if (sum <= 0.0) return;
    setState(() {
      _distWeight = double.parse((_distWeight / sum).toStringAsFixed(2));
      _sizeWeight = double.parse((_sizeWeight / sum).toStringAsFixed(2));
      _prefWeight = double.parse((_prefWeight / sum).toStringAsFixed(2));
      _demandWeight = double.parse((1.0 - (_distWeight + _sizeWeight + _prefWeight)).toStringAsFixed(2));
    });
  }

  void _resetToDefaults() {
    const d = ScoringWeights();
    setState(() {
      _distWeight = d.distanceWeight;
      _sizeWeight = d.sizeFitWeight;
      _prefWeight = d.preferenceWeight;
      _demandWeight = d.demandWeight;
      _minImprovementMeters = d.minImprovementMeters.toDouble();
      _minScorePoints = d.minScoreImprovementPoints;
      _offerTimeoutSec = d.offerTimeoutSeconds.toDouble();
      _triggerEtaMinutes = d.upgradeTriggerEtaMinutes.toDouble();
    });
  }

  void _applyWeights() {
    final updated = ScoringWeights(
      distanceWeight: _distWeight,
      sizeFitWeight: _sizeWeight,
      preferenceWeight: _prefWeight,
      demandWeight: _demandWeight,
      minImprovementMeters: _minImprovementMeters.toInt(),
      minScoreImprovementPoints: _minScorePoints,
      offerTimeoutSeconds: _offerTimeoutSec.toInt(),
      upgradeTriggerEtaMinutes: _triggerEtaMinutes.toInt(),
    );

    context.read<ParkingStateManager>().updateScoringWeights(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Updated re-optimization hyperparameter weights (SYS-01 & SYS-03)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.sheetR,
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.slotTaken,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: c.accent, size: 24),
                      const SizedBox(width: AppSpace.sm),
                      Text(
                        'Engine Tuning',
                        style: AppText.h2.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _resetToDefaults,
                    child: Text(
                      'Reset Defaults',
                      style: AppText.caption.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Configure multi-criteria weights and in-transit upgrade triggering parameters.',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.lg),

              // Objective Function Preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.cardSm),
                  border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scoring Function (SYS-01):',
                      style: AppText.label.copyWith(color: c.accent, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'S = ${_distWeight.toStringAsFixed(2)}·Sdist + ${_sizeWeight.toStringAsFixed(2)}·Ssize + ${_prefWeight.toStringAsFixed(2)}·Spref - ${_demandWeight.toStringAsFixed(2)}·Pdemand',
                      style: AppText.caption.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.lg),
              Text(
                'Multi-Criteria Component Weights',
                style: AppText.title.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: AppSpace.sm),

              _buildSlider(
                title: 'Walking Distance Weight (wd)',
                value: _distWeight,
                min: 0.1,
                max: 0.9,
                divisions: 16,
                unit: '',
                onChanged: (v) => setState(() => _distWeight = v),
                c: c,
              ),

              _buildSlider(
                title: 'Vehicle Size Fit Weight (wz)',
                value: _sizeWeight,
                min: 0.1,
                max: 0.9,
                divisions: 16,
                unit: '',
                onChanged: (v) => setState(() => _sizeWeight = v),
                c: c,
              ),

              _buildSlider(
                title: 'Driver Preference Weight (wp)',
                value: _prefWeight,
                min: 0.0,
                max: 0.5,
                divisions: 10,
                unit: '',
                onChanged: (v) => setState(() => _prefWeight = v),
                c: c,
              ),

              _buildSlider(
                title: 'Lot Congestion Penalty (wu)',
                value: _demandWeight,
                min: 0.0,
                max: 0.4,
                divisions: 8,
                unit: '',
                onChanged: (v) => setState(() => _demandWeight = v),
                c: c,
              ),

              const SizedBox(height: AppSpace.lg),
              Text(
                'Upgrade Triggering Thresholds (SYS-03)',
                style: AppText.title.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: AppSpace.sm),

              _buildSlider(
                title: 'Min Distance Delta (Δd)',
                value: _minImprovementMeters,
                min: 10,
                max: 120,
                divisions: 11,
                unit: ' m',
                onChanged: (v) => setState(() => _minImprovementMeters = v),
                c: c,
              ),

              _buildSlider(
                title: 'Min Score Improvement (ΔS)',
                value: _minScorePoints,
                min: 5,
                max: 40,
                divisions: 7,
                unit: ' pts',
                onChanged: (v) => setState(() => _minScorePoints = v),
                c: c,
              ),

              _buildSlider(
                title: 'Upgrade Offer Hold Timeout',
                value: _offerTimeoutSec,
                min: 15,
                max: 120,
                divisions: 7,
                unit: ' s',
                onChanged: (v) => setState(() => _offerTimeoutSec = v),
                c: c,
              ),

              _buildSlider(
                title: 'Trigger ETA Window (Window <= X)',
                value: _triggerEtaMinutes,
                min: 3,
                max: 20,
                divisions: 17,
                unit: ' min',
                onChanged: (v) => setState(() => _triggerEtaMinutes = v),
                c: c,
              ),

              // Live Weight Sum & Validation Card (SYS-01 Rigor)
              Container(
                margin: const EdgeInsets.only(top: AppSpace.sm),
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: _isValidSum ? c.accentSoft.withValues(alpha: 0.3) : c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.cardSm),
                  border: Border.all(
                    color: _isValidSum ? c.accent : c.danger,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isValidSum ? Icons.check_circle_rounded : Icons.warning_rounded,
                      color: _isValidSum ? c.accent : c.danger,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weight Sum: ${(_currentSum * 100).toStringAsFixed(1)}% (Target: 100.0%)',
                            style: AppText.caption.copyWith(
                              color: _isValidSum ? c.accent : c.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _isValidSum
                                ? 'Normalized valid distribution (Σw = 1.0 ± 0.001)'
                                : 'Weights must sum to 1.0 (±0.001) to apply changes.',
                            style: AppText.caption.copyWith(
                              color: c.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isValidSum)
                      TextButton(
                        onPressed: _normalizeWeights,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Normalize',
                          style: AppText.caption.copyWith(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              PrimaryButton(
                text: _isValidSum ? 'Apply Hyperparameters' : 'Sum Must Equal 1.0',
                onPressed: _isValidSum ? _applyWeights : null,
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
    required AppColors c,
  }) {
    final display = unit.isEmpty
        ? value.toStringAsFixed(2)
        : '${value.toInt()}$unit';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppText.caption.copyWith(color: c.textSecondary)),
              Text(
                display,
                style: AppText.caption.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: c.accent,
              inactiveTrackColor: c.divider,
              thumbColor: c.accent,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
