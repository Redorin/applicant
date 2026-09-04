import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../shell/toast_provider.dart';
import 'master_data_provider.dart';
import 'widgets/form_bits.dart';

/// Call before any action that would replace or leave a dirty Master Data
/// draft. Returns true when it is safe to proceed (nothing dirty, saved,
/// or explicitly discarded); false when the user cancelled.
///
/// Captures the [MasterDataController] notifier **before** the async dialog
/// gap so that state mutations (discard / save) work even if the calling
/// widget's `ref` becomes stale while the dialog is open.
Future<bool> resolveUnsavedChanges(BuildContext context, WidgetRef ref) async {
  final state = ref.read(masterDataProvider);
  if (state.draft == null || !state.dirty) return true;

  // Capture notifiers before the async gap — the calling widget (sidebar
  // rail / drawer) can be rebuilt (e.g. health-badge tick) while the dialog
  // is open, making `ref` stale.
  final notifier = ref.read(masterDataProvider.notifier);
  final toast = ref.read(toastProvider.notifier);

  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit_note, color: AppColors.warnInk, size: 22),
          SizedBox(width: 8),
          Text('Unsaved changes'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: const Text(
          'This record has edits that haven\'t been saved. '
          'Save them before leaving?',
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop('discard'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
          child: const Text('Discard'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Keep editing'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );

  switch (choice) {
    case 'discard':
      notifier.discardDraft();
      return true;
    case 'save':
      try {
        final ok = await notifier.save();
        if (ok) {
          toast.show('Saved');
          return true;
        }
        return false;
      } on ApiException catch (e) {
        if (context.mounted && e.errors.isNotEmpty) {
          await showValidationErrors(context, e.errors);
        } else {
          toast.show('Save failed: ${e.message}');
        }
        return false;
      } catch (_) {
        toast.show('Save failed — is the service running?');
        return false;
      }
    default:
      return false;
  }
}
