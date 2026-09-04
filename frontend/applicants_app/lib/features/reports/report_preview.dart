import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../auth/auth_provider.dart';
import '../shell/toast_provider.dart';

/// In-app preview for a generated PDF, with Print, Save-a-copy, and
/// open-externally actions — replaces the straight-to-viewer flow.
Future<void> showReportPreview(
  BuildContext context,
  WidgetRef ref, {
  required Uint8List bytes,
  required String suggestedFileName,
}) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 46,
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.white, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Report preview',
                      style: AppTypography.bodyStrong.copyWith(color: Colors.white)),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_alt, size: 14),
                  label: const Text('Save a copy…'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  onPressed: () async {
                    final location = await getSaveLocation(
                      suggestedName: suggestedFileName,
                      acceptedTypeGroups: const [
                        XTypeGroup(label: 'PDF', extensions: ['pdf']),
                      ],
                    );
                    if (location == null) return;
                    await File(location.path).writeAsBytes(bytes);
                    unawaited(ref.read(apiClientProvider).post('/api/audit-log', body: {
                      'entityType': 'report',
                      'action': 'save_copy',
                      'detail': suggestedFileName,
                    }));
                    ref
                        .read(toastProvider.notifier)
                        .show('Saved to ${location.path.split(Platform.pathSeparator).last}');
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) async => bytes,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: suggestedFileName,
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    ),
  );
}
