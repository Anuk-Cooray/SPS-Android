import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/parking_state_manager.dart';
import 'telemetry_exporter.dart';

enum ExportDatasetType {
  eventsCsv,
  benchmarkJson,
  scoresMatrixCsv;

  String get title => switch (this) {
        ExportDatasetType.eventsCsv => 'Events (CSV)',
        ExportDatasetType.benchmarkJson => 'System (JSON)',
        ExportDatasetType.scoresMatrixCsv => 'Bay Scores (CSV)',
      };

  String get fileExtension => switch (this) {
        ExportDatasetType.eventsCsv => 'csv',
        ExportDatasetType.benchmarkJson => 'json',
        ExportDatasetType.scoresMatrixCsv => 'csv',
      };

  String get description => switch (this) {
        ExportDatasetType.eventsCsv =>
          'RFC-4180 audit trail of reservation lifecycle events and upgrade decisions.',
        ExportDatasetType.benchmarkJson =>
          'Structured benchmark dataset containing model weights, thresholds, and event objects.',
        ExportDatasetType.scoresMatrixCsv =>
          'Multi-criteria scoring matrix evaluated across every campus slot (SYS-01).',
      };
}

class TelemetryExportModal extends StatefulWidget {
  const TelemetryExportModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TelemetryExportModal(),
    );
  }

  @override
  State<TelemetryExportModal> createState() => _TelemetryExportModalState();
}

class _TelemetryExportModalState extends State<TelemetryExportModal> {
  ExportDatasetType _selectedType = ExportDatasetType.eventsCsv;
  bool _copied = false;

  String _generateContent(ParkingStateManager state) {
    final vehicle = state.currentUser.defaultVehicle ??
        const Vehicle(
          id: 'v-default',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    switch (_selectedType) {
      case ExportDatasetType.eventsCsv:
        return TelemetryExporter.eventsToCsv(state.events);
      case ExportDatasetType.benchmarkJson:
        return TelemetryExporter.eventsToJson(
          events: state.events,
          weights: state.scoringWeights,
        );
      case ExportDatasetType.scoresMatrixCsv:
        return TelemetryExporter.slotScoresToCsv(
          lots: state.lots,
          vehicle: vehicle,
          preferences: state.currentUser.preferences,
          engine: state.engine,
        );
    }
  }

  void _handleCopy(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      setState(() => _copied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${_selectedType.title} dataset to clipboard.'),
          duration: const Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final content = _generateContent(state);
    final lineCount = content.split('\n').length;
    final charCount = content.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.sheetR,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Telemetry Data',
                    style: AppText.h2.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SLIIT Research Project J26-IT-335',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: c.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.md),

          // Dataset Type Selection Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ExportDatasetType.values.map((type) {
                final isSelected = _selectedType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type.title),
                    selected: isSelected,
                    selectedColor: c.primary,
                    backgroundColor: c.surfaceMuted,
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
                          _copied = false;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          // Description & Metrics Badge
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.cardSm),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.accent),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    _selectedType.description,
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    '$lineCount lines · ${(charCount / 1024).toStringAsFixed(1)} KB',
                    style: AppText.caption.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Code Monospace Preview Box
          Text(
            'DATA PREVIEW (${_selectedType.fileExtension.toUpperCase()})',
            style: AppText.overline.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpace.xs),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(AppRadius.cardSm),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  text: _copied ? 'Copied to Clipboard!' : 'Copy to Clipboard',
                  icon: _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
                  onPressed: () => _handleCopy(content),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(80, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
