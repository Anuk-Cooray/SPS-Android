import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/ai_occupancy_service.dart';
import '../../data/services/parking_state_manager.dart';

/// Captures a JPEG on the device, uploads it to FastAPI, then displays the
/// backend's YOLO/polygon annotated frame. No model is stored or run on Android.
class CameraDetectionScreen extends StatefulWidget {
  const CameraDetectionScreen({super.key});

  @override
  State<CameraDetectionScreen> createState() => _CameraDetectionScreenState();
}

class _CameraDetectionScreenState extends State<CameraDetectionScreen> {
  final _picker = ImagePicker();
  final _service = AiOccupancyService();
  Uint8List? _capturedImage;
  int? _resultKey;
  bool _uploading = false;
  String? _error;

  Future<void> _captureAndDetect() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      imageQuality: 88,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final parkingState = context.read<ParkingStateManager>();
    setState(() {
      _capturedImage = bytes;
      _resultKey = null;
      _error = null;
      _uploading = true;
    });
    try {
      await _service.uploadImage(bytes, filename: image.name);
      await parkingState.refreshAiOccupancy();
      if (mounted) {
        setState(() => _resultKey = DateTime.now().millisecondsSinceEpoch);
      }
    } on AiApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not reach the parking detection server.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = context.watch<ParkingStateManager>();
    final lot = state.lots.firstWhere(
      (lot) => lot.id == ParkingStateManager.aiLotId,
    );
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Camera occupancy detection')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Text(
            'Capture parking area',
            style: AppText.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Your photo is processed by the local YOLOv8 server. Keep the camera viewpoint calibrated with the parking-slot polygons.',
            style: AppText.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            height: 260,
            child: _capturedImage == null
                ? _EmptyPreview(onCapture: _captureAndDetect)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Image.memory(_capturedImage!, fit: BoxFit.cover),
                  ),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _uploading ? null : _captureAndDetect,
            icon: const Icon(Icons.camera_alt_rounded),
            label: Text(
              _capturedImage == null ? 'Open camera' : 'Capture another image',
            ),
          ),
          if (_uploading) ...[
            const SizedBox(height: AppSpace.md),
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Detecting vehicles and parking slots…',
              style: AppText.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(_error!, style: AppText.body.copyWith(color: Colors.red)),
          ],
          if (_resultKey != null) ...[
            const SizedBox(height: AppSpace.xl),
            Text(
              'YOLO detection preview',
              style: AppText.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Image.network(
                AiOccupancyService.processedImageUrl(_resultKey),
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    'Annotated preview was not available from the server.',
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            _OccupancySummary(
              available: lot.freeSlots,
              occupied: lot.slots
                  .where((slot) => slot.state == SlotState.taken)
                  .length,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onCapture});
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onCapture,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Center(child: Icon(Icons.camera_alt_outlined, size: 56)),
      ),
    );
  }
}

class _OccupancySummary extends StatelessWidget {
  const _OccupancySummary({required this.available, required this.occupied});
  final int available;
  final int occupied;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _CountCard(
          label: 'Available',
          count: available,
          color: Colors.green,
        ),
      ),
      const SizedBox(width: AppSpace.md),
      Expanded(
        child: _CountCard(
          label: 'Occupied / booked',
          count: occupied,
          color: Colors.red,
        ),
      ),
    ],
  );
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Column(
      children: [
        Text('$count', style: AppText.h2.copyWith(color: color)),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}
