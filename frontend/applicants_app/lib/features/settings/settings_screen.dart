import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../lookups/lookups_provider.dart';
import '../master_data/widgets/form_bits.dart';
import '../shell/toast_provider.dart';
import 'settings_provider.dart';

/// Same placeholder gate as the old app's "Parameters Setup" password —
/// a confirmation step against accidental edits, not real security.
/// Override at build time via: --dart-define=SETTINGS_GATE_PW=yourpassword
const _settingsGatePw = String.fromEnvironment('SETTINGS_GATE_PW',
    defaultValue: '33');

Future<bool> showSettingsGate(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Parameters setup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Editing these lists affects every applicant record. '
            'Enter the parameters password to continue.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: kInputDecoration.copyWith(labelText: 'Password'),
              onSubmitted: (v) =>
                  Navigator.of(context).pop(v == _settingsGatePw),
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text == _settingsGatePw),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: settingsTabs.length, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(settingsProvider);
      if (state.tabs.isEmpty) {
        ref.read(settingsProvider.notifier).loadAll();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    try {
      await ref.read(settingsProvider.notifier).saveAll();
      if (mounted) {
        ref.read(toastProvider.notifier).show('Parameter lists saved');
      }
    } on ApiException catch (e) {
      if (mounted) {
        await showValidationErrors(context, [e.message]);
      }
    } catch (_) {
      if (mounted) {
        ref.read(toastProvider.notifier).show('Save failed — is the service running?');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);

    if (state.tabs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: PageHeader(
            title: 'Settings',
            parentTitle: 'Master Data',
            onParentTap: () => context.go('/master-data'),
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 15),
                label: const Text('Back to Master Data'),
                onPressed: () => context.go('/master-data'),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(18, AppSpacing.md, 18, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warnBack,
            borderRadius: AppRadius.smAll,
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 15, color: AppColors.warnInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'These lists feed every dropdown in the app. Changes apply after "Save all".',
                  style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600, color: AppColors.warnInk),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.line),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.actionBlue,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.actionBlue,
            labelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            tabs: [
              for (final t in settingsTabs)
                Tab(
                  text: state.tabs[t.key]?.dirty ?? false
                      ? '${t.label} •'
                      : t.label,
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final t in settingsTabs) _SettingsTable(config: t),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Row(
            children: [
              const Spacer(),
              if (state.anyDirty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('Unsaved changes',
                      style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600, color: AppColors.warnInk)),
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(state.isSaving ? 'Saving…' : 'Save all'),
                onPressed:
                    state.anyDirty && !state.isSaving ? _saveAll : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTable extends ConsumerWidget {
  const _SettingsTable({required this.config});
  final SettingsTabConfig config;

  Future<void> _editRow(BuildContext context, WidgetRef ref,
      {int? index, Map<String, dynamic>? existing}) async {
    final lookups = ref.read(lookupsProvider).value;
    final draft = Map<String, dynamic>.from(existing ?? {});
    final controllers = <String, TextEditingController>{
      for (final c in config.columns)
        if (c.type == SettingsColumnType.text)
          c.field: TextEditingController(text: (draft[c.field] ?? '').toString()),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'Add ${config.label}' : 'Edit ${config.label}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in config.columns) ...[
                if (c.type == SettingsColumnType.text)
                  Labeled(
                    label: c.label,
                    child: TextField(
                      controller: controllers[c.field],
                      style: kValueStyle,
                      decoration: kInputDecoration,
                    ),
                  )
                else
                  Labeled(
                    label: c.label,
                    child: Builder(builder: (context) {
                      final provinces = lookups?.provinces ?? <ProvinceRow>[];
                      String? nameOf(int? id) {
                        for (final p in provinces) {
                          if (p.id == id) return p.province;
                        }
                        return null;
                      }

                      return SearchableDropdown(
                        options: [for (final p in provinces) p.province],
                        value: nameOf(draft[c.field] as int?),
                        onChanged: (name) {
                          for (final p in provinces) {
                            if (p.province == name) {
                              draft[c.field] = p.id;
                              return;
                            }
                          }
                          draft[c.field] = null;
                        },
                      );
                    }),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply')),
        ],
      ),
    );

    if (saved ?? false) {
      for (final entry in controllers.entries) {
        draft[entry.key] = entry.value.text.trim();
      }
      ref.read(settingsProvider.notifier).upsertRow(config.key, index, draft);
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(
        settingsProvider.select((s) => s.tabs[config.key]));
    final rows = tabState?.rows ?? const [];
    final lookups = ref.watch(lookupsProvider).value;

    String cellText(Map<String, dynamic> row, SettingsColumn c) {
      final v = row[c.field];
      if (c.type == SettingsColumnType.provincePicker) {
        final id = v as int?;
        if (id == null) return '—';
        for (final p in lookups?.provinces ?? <ProvinceRow>[]) {
          if (p.id == id) return p.province;
        }
        return '#$id';
      }
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? '—' : s;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface2,
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                for (final c in config.columns)
                  SizedBox(
                    width: c.width,
                    child: Text(c.label.toUpperCase(), style: AppTypography.sectionTitle),
                  ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add'),
                  style: AppButtonStyles.compact,
                  onPressed: () => _editRow(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemExtent: 52,
              itemBuilder: (context, i) {
                final row = rows[i];
                return InkWell(
                  onTap: () =>
                      _editRow(context, ref, index: i, existing: row),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: i.isOdd ? AppColors.surface2 : AppColors.surface,
                      border: const Border(
                          bottom:
                              BorderSide(color: AppColors.line, width: .5)),
                    ),
                    child: Row(
                      children: [
                        for (final c in config.columns)
                          SizedBox(
                            width: c.width,
                            child: Text(cellText(row, c),
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 15, color: AppColors.danger),
                          tooltip: 'Remove',
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Remove this entry?',
                              message:
                                  'It will be deleted from the list when you press "Save all".',
                              confirmLabel: 'Remove',
                            );
                            if (ok) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .deleteRow(config.key, i);
                            }
                          },
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
}
