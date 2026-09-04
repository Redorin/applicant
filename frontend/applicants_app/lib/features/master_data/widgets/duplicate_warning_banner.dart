import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../models/master_data.dart';
import '../../../shared/widgets/initial_avatar.dart';
import '../master_data_provider.dart';

/// Full-width warning banner shown while the surname/first-name (+ optional
/// birthdate) the encoder is typing matches an existing record — an upgrade
/// of the old inline warning chip into a banner that actually lists the
/// matching record(s), reusing the same debounced [checkDuplicate] check
/// (see master_data_provider.dart) rather than adding a second check.
class DuplicateWarningBanner extends ConsumerWidget {
  const DuplicateWarningBanner({
    super.key,
    required this.warning,
    required this.matches,
  });

  final DuplicateWarning warning;
  final List<SearchRow> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = warning == DuplicateWarning.nameAndBirth
        ? 'A record with this name and birthdate already exists.'
        : 'Same name already on file — check the date of birth.';

    return Semantics(
      liveRegion: true,
      label: 'Possible duplicate applicant warning',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warnBack,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.warnInk.withValues(alpha: .25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warnInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Possible duplicate detected',
                      style: AppTypography.bodyStrong.copyWith(color: AppColors.warnInk)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(message, style: AppTypography.helper.copyWith(color: AppColors.warnInk)),
            if (matches.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final match in matches)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      InitialAvatar(name: match.displayName, radius: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(match.displayName, style: AppTypography.bodyStrong),
                            if ((match.municipality ?? '').trim().isNotEmpty)
                              Text(match.municipality!.trim(), style: AppTypography.caption),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/master-data?id=${match.id}'),
                        child: const Text('View existing record'),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () =>
                    ref.read(masterDataProvider.notifier).dismissDuplicateWarning(),
                child: const Text('Continue anyway'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
