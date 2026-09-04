import 'dart:async';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_button_styles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/status_color.dart';
import '../../models/master_data.dart';
import '../../shared/widgets/app_date_picker.dart';
import '../../shared/widgets/hover_scale.dart';
import '../../shared/widgets/page_header.dart';
import '../data_health/statuses_provider.dart';
import '../lookups/lookups_provider.dart';
import '../reports/report_preview.dart';
import '../reports/reports_provider.dart';
import '../settings/settings_screen.dart';
import '../shell/toast_provider.dart';
import 'master_data_provider.dart';
import 'recently_opened_provider.dart';
import 'sticky_fields.dart';
import 'unsaved_guard.dart';
import 'widgets/application_editor.dart';
import 'widgets/duplicate_warning_banner.dart';
import 'widgets/form_bits.dart';

const _genderOptions = ['Male', 'Female'];
const _civilStatusOptions = ['Single', 'Married', 'Widowed', 'Separated'];

/// Layout constants for the Master Data page redesign.
const _contentPadding = 16.0;
const _cardGap = 10.0;
const _inputHeight = 42.0;

/// Enter moves to the next field, so a whole record can be typed without
/// touching the mouse.
void _nextField(BuildContext context) => FocusScope.of(context).nextFocus();

/// Short "3m ago" / "2h ago" / "Jul 19" label for the Recent popover.
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dt);
}

class MasterDataScreen extends ConsumerStatefulWidget {
  const MasterDataScreen({super.key, this.initialSearch, this.initialId});

  /// Set when arriving from the global search box.
  final String? initialSearch;

  /// Set when arriving from a browse-grid row click — loads directly.
  final int? initialId;

  @override
  ConsumerState<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends ConsumerState<MasterDataScreen> {
  // Groups the search field and its results dropdown for TapRegion so a tap
  // on a result (which is in a separate Overlay, not a descendant of the
  // field) still counts as "inside" — only a genuine tap elsewhere closes it.
  static const _searchTapGroup = 'master-data-search';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchLayerLink = LayerLink();
  Timer? _searchDebounce;
  OverlayEntry? _searchOverlayEntry;
  List<SearchRow> _searchOverlayResults = [];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeRouteArgs());
  }

  @override
  void didUpdateWidget(MasterDataScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialSearch != old.initialSearch ||
        widget.initialId != old.initialId) {
      _consumeRouteArgs();
    }
  }

  Future<void> _consumeRouteArgs() async {
    final controller = ref.read(masterDataProvider.notifier);
    if (widget.initialId != null) {
      // A browse-grid jump replaces the loaded record — guard dirty edits.
      final ok = await resolveUnsavedChanges(context, ref);
      if (ok) await controller.load(widget.initialId!);
      return;
    }
    final q = widget.initialSearch;
    if (q != null && q.trim().isNotEmpty) {
      _searchController.text = q;
      await controller.search(q);
      if (mounted) _searchFocus.requestFocus();
    }
    await _offerAutosaveRecovery();
  }

  /// If a crash left an unsaved draft behind, offer to bring it back the
  /// first time the screen opens with nothing loaded.
  Future<void> _offerAutosaveRecovery() async {
    final controller = ref.read(masterDataProvider.notifier);
    if (ref.read(masterDataProvider).draft != null) return;
    final info = await controller.peekAutosave();
    if (info == null || !mounted) return;

    final when = DateFormat('MMM d, h:mm a').format(info.savedAt);
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Recover unsaved work?'),
        content: Text(
          'An applicant record was being typed when the app closed '
          'unexpectedly:\n\n${info.displayName} — last kept at $when.\n\n'
          'Restore it and continue where you left off?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (restore == true) {
      final ok = await controller.restoreAutosave();
      if (ok && mounted) {
        ref.read(toastProvider.notifier).show('Draft restored — not saved yet');
      }
    } else {
      await controller.clearAutosave();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocus.removeListener(_onSearchFocusChange);
    _hideSearchOverlay();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // Same 400ms debounce as the old app's live search.
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      await ref.read(masterDataProvider.notifier).search(value);
      if (mounted) _updateSearchOverlay();
    });
  }

  // Hiding is handled by TapRegion.onTapOutside below (deterministic — no
  // race with the tap that's landing on a result). Gaining focus still
  // shows the dropdown if there are already results (e.g. after the
  // deep-link search-and-focus in _consumeRouteArgs).
  void _onSearchFocusChange() {
    if (_searchFocus.hasFocus) _updateSearchOverlay();
  }

  /// Floating results dropdown anchored under the search field — same
  /// style/behavior as the old topbar's global search, folded into Master
  /// Data's own search now that the topbar is gone.
  void _updateSearchOverlay() {
    final results = ref.read(masterDataProvider).searchResults;
    _searchOverlayResults = results;
    final show = results.isNotEmpty;
    if (!show) {
      _hideSearchOverlay();
      return;
    }
    if (_searchOverlayEntry == null) {
      _searchOverlayEntry = _buildSearchOverlayEntry();
      Overlay.of(context).insert(_searchOverlayEntry!);
    } else {
      _searchOverlayEntry!.markNeedsBuild();
    }
  }

  void _hideSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
  }

  OverlayEntry _buildSearchOverlayEntry() {
    final fmt = DateFormat('MMM dd, yyyy');
    return OverlayEntry(
      // Named to avoid shadowing the screen's own `context` below — this
      // dropdown's context gets torn down the moment _hideSearchOverlay()
      // runs, so anything after that (resolveUnsavedChanges, navigation)
      // must use the Master Data screen's own, still-mounted context.
      builder: (overlayContext) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _searchLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 50),
          child: TapRegion(
            groupId: _searchTapGroup,
            onTapOutside: (_) => _hideSearchOverlay(),
            child: Material(
              elevation: 6,
              borderRadius: AppRadius.mdAll,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: AppRadius.mdAll,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _searchOverlayResults.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (itemContext, i) {
                    final r = _searchOverlayResults[i];
                    final pal = statusPaletteFor(r.latestStatus);
                    return ListTile(
                      dense: true,
                      title: Text(r.displayName, style: AppTypography.bodyStrong),
                      subtitle: Text(
                        [
                          if ((r.municipality ?? '').isNotEmpty) r.municipality,
                          if (r.dbirth != null) 'b. ${fmt.format(r.dbirth!)}',
                        ].join(' · '),
                        style: AppTypography.caption,
                      ),
                      trailing: (r.latestStatus ?? '').trim().isEmpty
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: pal.background,
                                borderRadius: AppRadius.pillAll,
                              ),
                              child: Text(r.latestStatus!,
                                  style: AppTypography.chip.copyWith(color: pal.ink)),
                            ),
                      onTap: () async {
                        _hideSearchOverlay();
                        _searchFocus.unfocus();
                        final ok = await resolveUnsavedChanges(context, ref);
                        if (!ok || !mounted) return;
                        try {
                          await ref.read(masterDataProvider.notifier).load(r.id);
                        } catch (_) {
                          if (mounted) {
                            ref.read(toastProvider.notifier)
                                .show('Could not open that applicant.');
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final controller = ref.read(masterDataProvider.notifier);
    try {
      final ok = await controller.save();
      if (ok && mounted) {
        ref.read(toastProvider.notifier).show('Saved');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errors.isNotEmpty) {
        await showValidationErrors(context, e.errors);
      } else {
        ref.read(toastProvider.notifier).show('Save failed: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        ref.read(toastProvider.notifier).show('Save failed — is the service running?');
      }
    }
  }

  Future<void> _archive() async {
    final draft = ref.read(masterDataProvider).draft;
    if (draft == null || draft.isNew) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Archive this applicant?',
      message:
          '${draft.surname}, ${draft.firstname} will be archived and hidden from '
          'all lists. The record is never deleted and can be restored by an administrator.',
      confirmLabel: 'Archive',
    );
    if (!confirmed) return;
    try {
      await ref.read(masterDataProvider.notifier).archive();
      if (mounted) ref.read(toastProvider.notifier).show('Applicant archived');
    } catch (_) {
      if (mounted) ref.read(toastProvider.notifier).show('Archive failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(masterDataProvider);
    final lookupsAsync = ref.watch(lookupsProvider);

    return lookupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load lookup lists: $e', style: AppTypography.helper),
          const SizedBox(height: 10),
          OutlinedButton(
              onPressed: () => ref.invalidate(lookupsProvider),
              child: const Text('Retry')),
        ]),
      ),
      data: (lookups) => CallbackShortcuts(
        bindings: {
          // Ctrl+S saves, Ctrl+N starts a new applicant.
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (state.draft != null && !state.isSaving) _save();
          },
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              () async {
            final ok = await resolveUnsavedChanges(context, ref);
            if (ok) ref.read(masterDataProvider.notifier).newApplicant();
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: PageHeader(
                  title: 'Master Data',
                  actions: [_buildSearchField()],
                ),
              ),
              _buildToolbar(state),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.draft == null
                        ? _buildEmptyState()
                        : _buildForm(state, lookups),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRecent(int id) async {
    final ok = await resolveUnsavedChanges(context, ref);
    if (ok && mounted) ref.read(masterDataProvider.notifier).load(id);
  }

  /// Title-row search field — 280px, pill-shaped, floats its own results
  /// overlay under it. Lives in [PageHeader]'s `actions` now instead of the
  /// toolbar, per the title-row layout.
  Widget _buildSearchField() {
    return TapRegion(
      groupId: _searchTapGroup,
      child: CompositedTransformTarget(
        link: _searchLayerLink,
        child: SizedBox(
          width: 280,
          height: 34,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            style: kValueStyle.copyWith(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search applicants by name…',
              prefixIcon: const Icon(Icons.search, size: 14, color: AppColors.muted),
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.smAll,
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.smAll,
                borderSide: const BorderSide(color: AppColors.selectedBorder, width: 1.4),
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(MasterDataState state) {
    final recent = ref.watch(recentlyOpenedProvider);

    // Ghost/text secondary actions scroll horizontally on the left (fine if
    // you have to scroll to reach one), while New/Save — the actions you
    // need on every record — are pinned on the right so they're always
    // visible and never clipped off the edge of the window.
    final scrollItems = <Widget>[
      if (recent.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'Jump back to a recently opened applicant',
          itemBuilder: (context) => [
            for (final r in recent)
              PopupMenuItem<int>(
                value: r.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(r.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body),
                    ),
                    const SizedBox(width: 12),
                    Text(_relativeTime(r.openedAt), style: AppTypography.caption),
                  ],
                ),
              ),
          ],
          onSelected: _openRecent,
          // PopupMenuButton already shows its own tooltip on hover, so this
          // button isn't wrapped in a second Tooltip like its siblings below.
          child: TextButton.icon(
            style: AppButtonStyles.ghost,
            icon: const Icon(Icons.history, size: 16),
            label: const Text('Recent'),
            onPressed: null,
          ),
        ),
      TextButton.icon(
        style: AppButtonStyles.ghost,
        icon: const Icon(Icons.tune, size: 16),
        label: const Text('Settings'),
        onPressed: () async {
          final ok = await showSettingsGate(context);
          if (ok && mounted && context.mounted) {
            context.go('/settings');
          }
        },
      ),
      TextButton.icon(
        style: AppButtonStyles.ghost,
        icon: const Icon(Icons.upload_file_outlined, size: 16),
        label: const Text('Import'),
        onPressed: () async {
          final ok = await resolveUnsavedChanges(context, ref);
          if (ok && mounted && context.mounted) {
            context.go('/import');
          }
        },
      ),
      TextButton.icon(
        style: AppButtonStyles.ghost,
        icon: const Icon(Icons.inventory_2_outlined, size: 16),
        label: const Text('Archived'),
        onPressed: () async {
          final ok = await resolveUnsavedChanges(context, ref);
          if (ok && mounted && context.mounted) {
            context.go('/archived');
          }
        },
      ),
      if (state.draft != null && !state.draft!.isNew)
        TextButton.icon(
          style: AppButtonStyles.ghostDanger,
          icon: const Icon(Icons.archive_outlined, size: 16),
          label: const Text('Archive'),
          onPressed: _archive,
        ),
      if (state.draft != null &&
          state.draft!.isNew &&
          state.stickiesApplied &&
          !state.dirty)
        Tooltip(
          message:
              'Municipality was carried over '
              'from the last saved applicant. Click × to start clean.',
          child: InputChip(
            avatar: const Icon(Icons.copy_all_outlined,
                size: 14, color: AppColors.actionBlue),
            label: Text(
              'Carried over: ${ref.read(stickyFieldsProvider)?.summary ?? ''}',
              style: AppTypography.caption,
            ),
            onDeleted: () {
              ref.read(stickyFieldsProvider.notifier).clear();
              // Draft is still pristine, so replacing it loses nothing.
              ref.read(masterDataProvider.notifier).newApplicant();
              ref
                  .read(toastProvider.notifier)
                  .show('Carried-over values cleared');
            },
          ),
        ),
    ];

    final pinnedItems = <Widget>[
      HoverScale(
        child: OutlinedButton.icon(
          style: AppButtonStyles.compact,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New'),
          onPressed: () async {
            final ok = await resolveUnsavedChanges(context, ref);
            if (ok) ref.read(masterDataProvider.notifier).newApplicant();
          },
        ),
      ),
      if (state.draft != null)
        HoverScale(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(state.isSaving ? 'Saving…' : 'Save'),
            onPressed: state.isSaving ? null : _save,
          ),
        ),
    ];

    Widget rowOf(List<Widget> row) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              row[i],
            ],
          ],
        );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface2,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: rowOf(scrollItems),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            width: 1,
            height: 28,
            color: AppColors.line,
          ),
          rowOf(pinnedItems),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_search_outlined,
              size: 44, color: AppColors.muted),
          const SizedBox(height: 12),
          Text('Find an applicant or start a new record',
              style: AppTypography.bodyStrong.copyWith(fontSize: 17)),
          const SizedBox(height: 4),
          const Text(
              'Search by name above, or click "New Applicant" to begin.',
              style: AppTypography.helper),
        ],
      ),
    );
  }

  // ---------------- the record form ----------------

  Widget _buildForm(MasterDataState state, Lookups lookups) {
    final d = state.draft!;
    // No epoch-keyed cards here — that used to force Flutter to fully
    // dispose and recreate all 5 cards' State (every controller, every
    // dropdown) on every newApplicant()/load(), which was the actual cause
    // of "New Applicant"/"load an existing applicant" feeling like a
    // freeze. Each card's State now survives across draft swaps and
    // resyncs its own controllers in didUpdateWidget when the draft
    // instance changes (see e.g. _PersonalInfoCardState.didUpdateWidget) —
    // that's what now prevents New Applicant/Load from showing stale text.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(_contentPadding),
      // Reading-order traversal matches the visual card layout, so Tab and
      // Enter walk the form top-to-bottom, left-to-right.
      child: FocusTraversalGroup(
        child: Column(
          children: [
            if (state.duplicateWarning != DuplicateWarning.none) ...[
              DuplicateWarningBanner(
                warning: state.duplicateWarning,
                matches: state.duplicateMatches,
              ),
              const SizedBox(height: _cardGap),
            ],
            _PersonalInfoSectionCard(draft: d),
            const SizedBox(height: _cardGap),
            // Qualifications (left) and Address (right) share a row so
            // they read as one glance instead of two stacked full-width
            // cards. IntrinsicHeight can't be used here — every field on
            // this card is a SearchableDropdown, and its internal
            // LayoutBuilder throws when asked for an intrinsic size — so
            // equal height is done via _EqualHeightPair instead.
            _EqualHeightPair(
              left: _AddressCard(draft: d, lookups: lookups),
              right: _QualificationsCard(draft: d, lookups: lookups),
            ),
            const SizedBox(height: _cardGap),
            _ApplicationsSectionCard(draft: d, lookups: lookups),
          ],
        ),
      ),
    );
  }
}

// ============ Section 1: personal information ============

/// Wraps [_PhotoSection] (fixed-width left column, right-border divider) and
/// [_PersonalInfoCard] (flexible right column) in one SectionCard, mirroring
/// how _ApplicationsSectionCard pairs PIC & Notes with the Applications table.
class _PersonalInfoSectionCard extends StatelessWidget {
  const _PersonalInfoSectionCard({required this.draft});
  final MasterDataDraft draft;

  static const _photoColumnWidth = 160.0;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Personal information',
      child: _EqualHeightPair(
        leftWidth: _photoColumnWidth,
        left: Container(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: _PhotoSection(draft: draft),
        ),
        right: _PersonalInfoCard(draft: draft),
      ),
    );
  }
}

/// 1x1 photo upload box. Owns its own preview-bytes state (like
/// _ApplicationsCard owns its own setState for add/edit/remove) instead of
/// routing through MasterDataState, since a freshly picked photo is transient
/// UI state that only becomes part of the record once _persist() uploads it.
class _PhotoSection extends ConsumerStatefulWidget {
  const _PhotoSection({required this.draft});
  final MasterDataDraft draft;

  @override
  ConsumerState<_PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends ConsumerState<_PhotoSection> {
  Uint8List? _previewBytes;
  String? _loadedForPath;

  @override
  void didUpdateWidget(_PhotoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different draft instance (New Applicant / Load) means any preview
    // bytes we're holding belong to the record that just got swapped out.
    if (!identical(oldWidget.draft, widget.draft)) {
      _previewBytes = null;
      _loadedForPath = null;
    }
  }

  Future<void> _pick() async {
    final bytes =
        await ref.read(masterDataProvider.notifier).pickPhoto();
    if (bytes != null && mounted) setState(() => _previewBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = widget.draft.photoPath;

    // Lazily fetch the saved photo the first time this draft shows one, and
    // whenever the path changes (e.g. save() reloaded the record with a
    // freshly uploaded photo) — but never once a fresher local pick exists.
    if (_previewBytes == null &&
        photoPath != null &&
        photoPath.isNotEmpty &&
        _loadedForPath != photoPath &&
        !widget.draft.isNew) {
      _loadedForPath = photoPath;
      ref
          .read(masterDataProvider.notifier)
          .fetchPhoto(widget.draft.id!)
          .then((bytes) {
        if (mounted && widget.draft.photoPath == photoPath) {
          setState(() => _previewBytes = bytes);
        }
      }).catchError((_) {});
    }

    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _pick,
            child: SizedBox(
              width: 110,
              height: 110,
              child: DottedBorder(
                borderType: BorderType.RRect,
                radius: const Radius.circular(8),
                color: AppColors.line,
                strokeWidth: 2,
                dashPattern: const [5, 4],
                padding: EdgeInsets.zero,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: AppColors.inputEmptyBg,
                  ),
                  child: _previewBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(_previewBytes!, fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, size: 22, color: AppColors.muted),
                            const SizedBox(height: 4),
                            Text('Click to upload\n1x1 photo',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption.copyWith(fontSize: 10)),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Max 2MB · JPG, PNG', style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _PersonalInfoCard extends ConsumerStatefulWidget {
  const _PersonalInfoCard({required this.draft});
  final MasterDataDraft draft;

  @override
  ConsumerState<_PersonalInfoCard> createState() => _PersonalInfoCardState();
}

class _PersonalInfoCardState extends ConsumerState<_PersonalInfoCard> {
  late final TextEditingController _surname =
      TextEditingController(text: widget.draft.surname);
  late final TextEditingController _firstname =
      TextEditingController(text: widget.draft.firstname);
  late final TextEditingController _midname =
      TextEditingController(text: widget.draft.midname);
  late final TextEditingController _ext =
      TextEditingController(text: widget.draft.ext);
  late final TextEditingController _contact =
      TextEditingController(text: widget.draft.contact);
  late final TextEditingController _contact2 =
      TextEditingController(text: widget.draft.contact2);

  @override
  void didUpdateWidget(_PersonalInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different `draft` object (not just an in-place edit — those mutate
    // the same instance, see MasterDataDraft) means New Applicant / Load
    // swapped in a different record. Resync the
    // controllers in place instead of relying on a remount, which used to
    // be forced via an epoch-keyed widget and was the actual cause of
    // Master Data feeling slow to load.
    if (!identical(oldWidget.draft, widget.draft)) {
      _surname.text = widget.draft.surname;
      _firstname.text = widget.draft.firstname;
      _midname.text = widget.draft.midname;
      _ext.text = widget.draft.ext;
      _contact.text = widget.draft.contact;
      _contact2.text = widget.draft.contact2;
    }
  }

  @override
  void dispose() {
    _surname.dispose();
    _firstname.dispose();
    _midname.dispose();
    _ext.dispose();
    _contact.dispose();
    _contact2.dispose();
    super.dispose();
  }

  int? get _age {
    final b = widget.draft.dbirth;
    if (b == null) return null;
    final now = DateTime.now();
    var age = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) age--;
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final controller = ref.read(masterDataProvider.notifier);
    final fmt = DateFormat('MMM dd, yyyy');

    return Column(
        children: [
          Row(children: [
            Expanded(
                flex: 2,
                child: Labeled(
                    label: 'Surname',
                    required: true,
                    child: SizedBox(
                      height: _inputHeight,
                      child: TextField(
                          controller: _surname,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _nextField(context),
                          style: kValueStyle,
                          decoration: kInputDecoration,
                          // Every fresh draft starts typing immediately.
                          autofocus: widget.draft.isNew,
                          onChanged: (v) {
                            d.surname = v;
                            controller.touch();
                            controller.checkDuplicateDebounced();
                          }),
                    ))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                flex: 2,
                child: Labeled(
                    label: 'First name',
                    required: true,
                    child: SizedBox(
                      height: _inputHeight,
                      child: TextField(
                          controller: _firstname,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _nextField(context),
                          style: kValueStyle,
                          decoration: kInputDecoration,
                          onChanged: (v) {
                            d.firstname = v;
                            controller.touch();
                            controller.checkDuplicateDebounced();
                          }),
                    ))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                flex: 2,
                child: Labeled(
                    label: 'Middle name',
                    child: SizedBox(
                      height: _inputHeight,
                      child: TextField(
                          controller: _midname,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _nextField(context),
                          style: kValueStyle,
                          decoration: kInputDecoration,
                          onChanged: (v) {
                            d.midname = v;
                            controller.touch();
                          }),
                    ))),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                flex: 2,
                child: Labeled(
                    label: 'Ext.',
                    child: SizedBox(
                      height: _inputHeight,
                      child: TextField(
                          controller: _ext,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _nextField(context),
                          style: kValueStyle,
                          decoration: kInputDecoration,
                          onChanged: (v) {
                            d.ext = v;
                            controller.touch();
                          }),
                    ))),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 170,
                child: Labeled(
                  label: 'Date of birth',
                  required: true,
                  child: SizedBox(
                    height: _inputHeight,
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        side: const BorderSide(color: AppColors.comboBorder),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final picked = await AppDatePicker.show(
                          context,
                          initialDate: d.dbirth ?? DateTime(1990),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => d.dbirth = picked);
                          controller.touch();
                          // Same trigger as the old app: leaving the DOB
                          // field fires the duplicate check.
                          controller.checkDuplicate();
                        }
                      },
                      child: Text(
                        d.dbirth == null ? 'Pick a date…' : fmt.format(d.dbirth!),
                        style: d.dbirth == null
                            ? kValueStyle.copyWith(color: AppColors.muted)
                            : kValueStyle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 170,
                child: Labeled(
                  label: 'Gender',
                  required: true,
                  child: SizedBox(
                    height: _inputHeight,
                    child: SearchableDropdown(
                      options: _genderOptions,
                      value: d.gender,
                      allowClear: false,
                      onChanged: (v) {
                        d.gender = v;
                        controller.touch();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 170,
                child: Labeled(
                  label: 'Civil status',
                  required: true,
                  child: SizedBox(
                    height: _inputHeight,
                    child: SearchableDropdown(
                      options: _civilStatusOptions,
                      value: d.civistat,
                      allowClear: false,
                      onChanged: (v) {
                        d.civistat = v;
                        controller.touch();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Labeled(
                  label: 'Contact no. 1',
                  required: true,
                  child: SizedBox(
                    height: _inputHeight,
                    child: TextField(
                      controller: _contact,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _nextField(context),
                      style: kValueStyle,
                      inputFormatters: [ContactNumberFormatter()],
                      decoration: kInputDecoration.copyWith(hintText: '09XX XXX XXXX'),
                      onChanged: (v) {
                        d.contact = v;
                        controller.touch();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Fills the rest of the row instead of leaving dead space next
              // to it — every other row in this card is packed edge-to-edge.
              Expanded(
                child: Labeled(
                  label: 'Contact no. 2',
                  child: SizedBox(
                    height: _inputHeight,
                    child: TextField(
                      controller: _contact2,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _nextField(context),
                      style: kValueStyle,
                      inputFormatters: [ContactNumberFormatter()],
                      decoration: kInputDecoration.copyWith(hintText: '09XX XXX XXXX'),
                      onChanged: (v) {
                        d.contact2 = v;
                        controller.touch();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_age != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [InfoChip('Age $_age')],
              ),
            ),
          ],
        ],
      );
  }
}

// ============ Section 2: address ============

class _AddressCard extends ConsumerStatefulWidget {
  const _AddressCard({required this.draft, required this.lookups});
  final MasterDataDraft draft;
  final Lookups lookups;

  @override
  ConsumerState<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends ConsumerState<_AddressCard> {
  late final TextEditingController _houseNo =
      TextEditingController(text: widget.draft.houseNo);
  late final TextEditingController _street =
      TextEditingController(text: widget.draft.street);
  late final TextEditingController _subdivision =
      TextEditingController(text: widget.draft.subdivision);
  late final TextEditingController _barangay =
      TextEditingController(text: widget.draft.barangay);
  late final TextEditingController _address =
      TextEditingController(text: widget.draft.address);

  /// True while the user is actively editing address parts — the only time
  /// the composed address may be rewritten (protects legacy free-text).
  bool _editingAddress = false;

  /// True once the user typed directly into "Address on record" — their
  /// text then wins over auto-composition until they clear the field.
  bool _manualAddress = false;

  /// Forces the Province dropdown to re-read its value only when province
  /// changed for a reason `DropdownMenu` can't pick up on its own (a new
  /// record loaded, or Municipality auto-filling it below) — NOT on every
  /// rebuild, and not when the user picks a province directly from this
  /// same dropdown (it already updates its own displayed text for that).
  int _provinceKeySeed = 0;

  @override
  void didUpdateWidget(_AddressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      _houseNo.text = widget.draft.houseNo;
      _street.text = widget.draft.street;
      _subdivision.text = widget.draft.subdivision;
      _barangay.text = widget.draft.barangay;
      _address.text = widget.draft.address;
      // Reset to what a fresh State would start with — otherwise a flag
      // left over from the previous record could suppress auto-composition
      // for this one.
      _editingAddress = false;
      _manualAddress = false;
      _provinceKeySeed++;
    }
  }

  @override
  void dispose() {
    _houseNo.dispose();
    _street.dispose();
    _subdivision.dispose();
    _barangay.dispose();
    _address.dispose();
    super.dispose();
  }

  /// "Ramos" → "Ramos st." (unless the encoder already typed st./street).
  static String _streetPart(String street) {
    final s = street.trim();
    if (s.isEmpty) return '';
    return RegExp(r'\b(st\.?|street)$', caseSensitive: false).hasMatch(s)
        ? s
        : '$s st.';
  }

  /// "Poblacion" → "Brgy. Poblacion" (unless already prefixed).
  static String _barangayPart(String barangay) {
    final s = barangay.trim();
    if (s.isEmpty) return '';
    return RegExp(r'^brgy\.?\s', caseSensitive: false).hasMatch(s)
        ? s
        : 'Brgy. $s';
  }

  void _recompose() {
    if (!_editingAddress || _manualAddress) return;
    final d = widget.draft;
    final parts = [
      d.houseNo.trim(),
      _streetPart(d.street),
      d.subdivision.trim(),
      _barangayPart(d.barangay),
      (d.municipality ?? '').trim(),
      (d.province ?? '').trim(),
    ].where((s) => s.isNotEmpty);
    d.address = parts.join(', ');
    _address.text = d.address;
  }

  Widget _partField(String label, TextEditingController textController,
      void Function(String) assign) {
    final controller = ref.read(masterDataProvider.notifier);
    return Labeled(
      label: label,
      child: SizedBox(
        height: _inputHeight,
        child: TextField(
          controller: textController,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _nextField(context),
          style: kValueStyle,
          decoration: kInputDecoration,
          onChanged: (v) {
            _editingAddress = true;
            assign(v);
            setState(_recompose);
            controller.touch();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final controller = ref.read(masterDataProvider.notifier);
    final lookups = widget.lookups;
    final muni = lookups.municipalByName(d.municipality);
    final district = (muni?.district ?? d.district).trim();

    final municipalNames = lookups.municipalsForProvince(d.province);
    final provinceNames = lookups.provinces.map((p) => p.province).toList();

    return SectionCard(
      title: 'Address',
      child: Column(
        children: [
          Row(children: [
            Expanded(
                child: _partField(
                    'House / Blk / Lot', _houseNo, (v) => d.houseNo = v)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                child: _partField('Street', _street, (v) => d.street = v)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
                child: _partField(
                    'Subdivision', _subdivision, (v) => d.subdivision = v)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                child:
                    _partField('Barangay', _barangay, (v) => d.barangay = v)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: Labeled(
                label: 'Province',
                required: true,
                child: SizedBox(
                  height: _inputHeight,
                  child: SearchableDropdown(
                    key: ValueKey('prov-$_provinceKeySeed'),
                    options: provinceNames,
                    value: d.province,
                    allowClear: false,
                    onChanged: (v) {
                      _editingAddress = true;
                      d.province = v;
                      d.municipality = '';
                      d.district = '';
                      setState(_recompose);
                      controller.touch();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Fills the rest of the row instead of leaving dead space next
            // to it — matches the fully-packed convention used elsewhere.
            Expanded(
              child: Labeled(
                label: 'Municipality',
                required: true,
                child: SizedBox(
                  height: _inputHeight,
                  child: SearchableDropdown(
                    options: municipalNames,
                    value: d.municipality,
                    allowClear: false,
                    onChanged: (v) {
                      _editingAddress = true;
                      d.municipality = v;
                      // Auto-backfill province from the municipals→provinces FK,
                      // as the old app did.
                      final m = lookups.municipalByName(v);
                      final p = m == null ? null : lookups.provinceOf(m);
                      if (p != null) {
                        d.province = p.province;
                        _provinceKeySeed++;
                      }
                      if (m != null) d.district = (m.district ?? '').trim();
                      setState(_recompose);
                      controller.touch();
                    },
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Labeled(
            label: 'Address on record',
            child: SizedBox(
              height: _inputHeight,
              child: TextField(
                controller: _address,
                style: kValueStyle,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _nextField(context),
                decoration: kInputDecoration.copyWith(
                    hintText:
                        'Auto-composed from the fields above — type to override, clear to re-compose'),
                onChanged: (v) {
                  d.address = v;
                  _manualAddress = v.trim().isNotEmpty;
                  if (!_manualAddress) {
                    // Field cleared → hand control back to composition.
                    _editingAddress = true;
                    setState(_recompose);
                  }
                  controller.touch();
                },
              ),
            ),
          ),
          if (district.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [InfoChip('District $district')],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============ Section 3: qualifications ============

class _QualificationsCard extends ConsumerStatefulWidget {
  const _QualificationsCard(
      {required this.draft, required this.lookups});
  final MasterDataDraft draft;
  final Lookups lookups;

  @override
  ConsumerState<_QualificationsCard> createState() =>
      _QualificationsCardState();
}

class _QualificationsCardState extends ConsumerState<_QualificationsCard> {
  late final TextEditingController _skills =
      TextEditingController(text: widget.draft.skills);
  late List<WorkExperienceEntry> _workEntries =
      decodeWorkExperience(widget.draft.experience);
  late final TextEditingController _training =
      TextEditingController(text: widget.draft.training);

  @override
  void didUpdateWidget(_QualificationsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      _skills.text = widget.draft.skills;
      _workEntries = decodeWorkExperience(widget.draft.experience);
      _training.text = widget.draft.training;
    }
  }

  @override
  void dispose() {
    _skills.dispose();
    _training.dispose();
    super.dispose();
  }

  void _syncExperience() {
    final controller = ref.read(masterDataProvider.notifier);
    widget.draft.experience = encodeWorkExperience(_workEntries);
    controller.touch();
  }

  String get _workExperienceLabel {
    final (y, m) = totalWorkingExperience(_workEntries);
    final count = _workEntries.length;
    final part1 = '$count ${count == 1 ? 'entry' : 'entries'}';
    if (y == 0 && m == 0) return '$part1 · No duration yet';
    final parts = <String>[
      if (y > 0) '$y ${y == 1 ? 'year' : 'years'}',
      if (m > 0) '$m ${m == 1 ? 'month' : 'months'}',
    ];
    return '$part1 · ${parts.join(', ')} total';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final controller = ref.read(masterDataProvider.notifier);
    final lookups = widget.lookups;

    return SectionCard(
      title: 'Qualifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Labeled(
                label: 'Education',
                required: true,
                child: SizedBox(
                  height: _inputHeight,
                  child: SearchableDropdown(
                    options: lookups.education,
                    value: d.education,
                    allowClear: false,
                    onChanged: (v) {
                      d.education = v;
                      controller.touch();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Labeled(
                label: 'Second education / course',
                child: SizedBox(
                  height: _inputHeight,
                  child: SearchableDropdown(
                    options: lookups.education,
                    value: d.education2,
                    allowClear: false,
                    hint: 'None',
                    onChanged: (v) {
                      d.education2 = v;
                      controller.touch();
                    },
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Labeled(
              label: 'Skills',
              child: SizedBox(
                height: _inputHeight,
                child: TextField(
                    controller: _skills,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _nextField(context),
                    style: kValueStyle,
                    decoration: kInputDecoration,
                    onChanged: (v) {
                      d.skills = v;
                      controller.touch();
                    }),
              )),
          const SizedBox(height: AppSpacing.md),
          Labeled(
            label: 'School graduated from',
            required: true,
            child: SizedBox(
              height: _inputHeight,
              child: SearchableDropdown(
                options: lookups.schools,
                value: d.school,
                allowClear: false,
                onChanged: (v) {
                  d.school = v;
                  controller.touch();
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Labeled(
            label: 'Eligibilities',
            required: true,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in d.eligibilities)
                  Chip(
                    label: Text(e,
                        style: AppTypography.chip.copyWith(color: AppColors.chipInk)),
                    backgroundColor: AppColors.chipBack,
                    side: BorderSide.none,
                    deleteIcon: const Icon(Icons.close,
                        size: 13, color: AppColors.chipInk),
                    onDeleted: () {
                      setState(() => d.eligibilities.remove(e));
                      controller.touch();
                    },
                  ),
                // Legacy single-text eligibility shown read-only until the
                // record is migrated to the chips model, as in the old app.
                if (d.eligibilities.isEmpty &&
                    (d.legacyEligibility ?? '').trim().isNotEmpty)
                  Tooltip(
                    message:
                        'Saved before the eligibility rework — add chips to replace it.',
                    child: Chip(
                      label: Text(d.legacyEligibility!,
                          style: AppTypography.chip.copyWith(color: AppColors.neutralInk)),
                      backgroundColor: AppColors.neutralBack,
                      side: BorderSide.none,
                    ),
                  ),
                // Eligibility types themselves are managed in Settings — this
                // just attaches one of the existing types to this applicant.
                if (lookups.eligibilities.any((e) => !d.eligibilities.contains(e)))
                  SizedBox(
                    width: 220,
                    height: _inputHeight,
                    child: SearchableDropdown(
                      options: lookups.eligibilities
                          .where((e) => !d.eligibilities.contains(e))
                          .toList(),
                      hint: 'Search eligibility…',
                      allowClear: false,
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => d.eligibilities.add(v));
                          controller.touch();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Labeled(
            label: 'Work experience',
            child: SizedBox(
              height: _inputHeight,
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: const BorderSide(color: AppColors.comboBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.work_outline, size: 16, color: AppColors.muted),
                label: Text(
                  _workEntries.isEmpty
                      ? 'No work experience added'
                       : _workExperienceLabel,
                  style: _workEntries.isEmpty
                      ? kValueStyle.copyWith(color: AppColors.muted)
                      : kValueStyle,
                ),
                onPressed: () async {
                  final result = await _showWorkExperienceDialog(
                    context,
                    List<WorkExperienceEntry>.from(_workEntries),
                  );
                  if (result != null) {
                    setState(() => _workEntries = result);
                    _syncExperience();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Labeled(
              label: 'Training',
              child: TextField(
                  controller: _training,
                  style: kValueStyle,
                  maxLines: 3,
                  minLines: 2,
                  decoration: kInputDecoration.copyWith(
                      hintText: 'Relevant trainings, certifications...'),
                  onChanged: (v) {
                    d.training = v;
                    controller.touch();
                  })),
        ],
      ),
    );
  }

  Future<List<WorkExperienceEntry>?> _showWorkExperienceDialog(
    BuildContext context,
    List<WorkExperienceEntry> initial,
  ) {
    return showDialog<List<WorkExperienceEntry>>(
      context: context,
      builder: (context) => _WorkExperienceDialog(initial: initial),
    );
  }
}

/// Dialog for editing work experience entries.
/// Returns the updated list on save, or null on cancel.
class _WorkExperienceDialog extends StatefulWidget {
  const _WorkExperienceDialog({required this.initial});
  final List<WorkExperienceEntry> initial;

  @override
  State<_WorkExperienceDialog> createState() => _WorkExperienceDialogState();
}

class _WorkExperienceDialogState extends State<_WorkExperienceDialog> {
  late final List<WorkExperienceEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.initial.map((e) => WorkExperienceEntry(
      name: e.name,
      start: e.start,
      end: e.end,
    )).toList();
  }

  String get _dialogTotalLabel {
    final (y, m) = totalWorkingExperience(_entries);
    if (y == 0 && m == 0) return 'Total: No duration calculated yet';
    final parts = <String>[
      if (y > 0) '$y ${y == 1 ? 'year' : 'years'}',
      if (m > 0) '$m ${m == 1 ? 'month' : 'months'}',
    ];
    return 'Total: ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM dd, yyyy');
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.chipBack,
                          borderRadius: AppRadius.smAll,
                        ),
                        child: const Icon(Icons.work_outline,
                            color: AppColors.chipInk, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text('Work Experience', style: AppTypography.dialogTitle),
                    ],
                  ),
                  if (_entries.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 42),
                      child: Text(
                        _dialogTotalLabel,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.actionBlue),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Scrollable entries
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No work experience added yet',
                            style: AppTypography.body
                                .copyWith(color: AppColors.muted),
                          ),
                        ),
                      ),
                    for (var i = 0; i < _entries.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _WorkExperienceEntryRow(
                        entry: _entries[i],
                        fmt: fmt,
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() => _entries.removeAt(i)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => setState(() => _entries.add(WorkExperienceEntry())),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add, size: 14, color: AppColors.actionBlue),
                            const SizedBox(width: 4),
                            Text(
                              'Add entry',
                              style: AppTypography.body.copyWith(
                                fontSize: 13,
                                color: AppColors.actionBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_entries),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single work-experience entry row inside the dialog.
class _WorkExperienceEntryRow extends StatefulWidget {
  const _WorkExperienceEntryRow({
    required this.entry,
    required this.fmt,
    required this.onChanged,
    required this.onRemove,
  });

  final WorkExperienceEntry entry;
  final DateFormat fmt;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_WorkExperienceEntryRow> createState() => _WorkExperienceEntryRowState();
}

class _WorkExperienceEntryRowState extends State<_WorkExperienceEntryRow> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.entry.name);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final fmt = widget.fmt;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Labeled(
            label: 'Position / role',
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _nameCtrl,
                style: kValueStyle.copyWith(fontSize: 13),
                decoration: kInputDecoration.copyWith(
                  hintText: 'e.g. Admin Aide, Office Staff, Cashier',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close,
                        size: 14, color: AppColors.muted),
                    tooltip: 'Remove',
                    onPressed: widget.onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll,
                        side: const BorderSide(color: AppColors.line),
                      ),
                    ),
                  ),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  e.name = v;
                  widget.onChanged();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Labeled(
                  label: 'Start date',
                  child: SizedBox(
                    height: 42,
                    width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                side: const BorderSide(color: AppColors.comboBorder),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                minimumSize: const Size(0, 42),
                              ),
                              onPressed: () async {
                                final picked = await AppDatePicker.show(
                                  context,
                                  initialDate: e.start ?? DateTime.now(),
                                  lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                                );
                              if (picked != null) {
                                setState(() => e.start = picked);
                                widget.onChanged();
                              }
                            },
                            child: Text(
                              e.start == null
                                  ? 'Pick a date…'
                                  : e.formatDate(e.start, e.startPrecision, fmt),
                              style: e.start == null
                                  ? kValueStyle.copyWith(
                                      fontSize: 13, color: AppColors.muted)
                                  : kValueStyle.copyWith(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          tooltip: 'Date precision',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: AppColors.muted,
                          ),
                          onSelected: (v) {
                            setState(() => e.startPrecision = v);
                            widget.onChanged();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'full',
                              child: Text('Full date', style: AppTypography.body),
                            ),
                            const PopupMenuItem(
                              value: 'monthYear',
                              child: Text('Month + Year', style: AppTypography.body),
                            ),
                            const PopupMenuItem(
                              value: 'yearOnly',
                              child: Text('Year only', style: AppTypography.body),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Labeled(
                  label: 'End date',
                  child: SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              side: const BorderSide(color: AppColors.comboBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 42),
                            ),
                            onPressed: () async {
                              final picked = await AppDatePicker.show(
                                context,
                                initialDate: e.end ?? DateTime.now(),
                                lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                              );
                              if (picked != null) {
                                setState(() => e.end = picked);
                                widget.onChanged();
                              }
                            },
                            child: Text(
                              e.end == null
                                  ? 'Pick a date…'
                                  : e.formatDate(e.end, e.endPrecision, fmt),
                              style: e.end == null
                                  ? kValueStyle.copyWith(
                                      fontSize: 13, color: AppColors.muted)
                                  : kValueStyle.copyWith(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          tooltip: 'Date precision',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: AppColors.muted,
                          ),
                          onSelected: (v) {
                            setState(() => e.endPrecision = v);
                            widget.onChanged();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'full',
                              child: Text('Full date', style: AppTypography.body),
                            ),
                            const PopupMenuItem(
                              value: 'monthYear',
                              child: Text('Month + Year', style: AppTypography.body),
                            ),
                            const PopupMenuItem(
                              value: 'yearOnly',
                              child: Text('Year only', style: AppTypography.body),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _openApplicantPdf(
    BuildContext context, WidgetRef ref, String path, String fileName) async {
  ref.read(toastProvider.notifier).show('Generating PDF…');
  try {
    final bytes = await ref.read(reportRunnerProvider).fetchPdf(path);
    if (context.mounted) {
      await showReportPreview(context, ref,
          bytes: bytes, suggestedFileName: fileName);
    }
  } catch (_) {
    ref.read(toastProvider.notifier).show('Unable to produce the document');
  }
}

class _ApplicationsCard extends ConsumerStatefulWidget {
  const _ApplicationsCard(
      {required this.draft, required this.lookups});
  final MasterDataDraft draft;
  final Lookups lookups;

  /// Proportional column widths (Date Applied, Position, Department, Status,
  /// Emp. Status, Interview, Recommendation, Date Hired, Final Status,
  /// Actions) — fixed so the table always fits the content area instead of
  /// needing horizontal scroll.
  static const _colFlex = [9, 15, 17, 8, 9, 9, 12, 9, 9, 7];

  static const _headers = [
    'DATE APPLIED', 'POSITION', 'DEPARTMENT', 'STATUS', 'EMP. STATUS',
    'INTERVIEW', 'RECOMMENDATION', 'DATE HIRED', 'FINAL STATUS', '',
  ];

  @override
  ConsumerState<_ApplicationsCard> createState() => _ApplicationsCardState();
}

// Unlike the other section cards, this one has no controllers of its own —
// it previously relied entirely on the parent form rebuilding on every
// touch() to refresh the DataTable after an add/edit/remove. Now that
// MasterDataState only notifies on a genuine change (see the == override in
// master_data_provider.dart), this card owns its own setState for those three
// mutations, mirroring the pattern _QualificationsCard already uses for its
// eligibility chips.
class _ApplicationsCardState extends ConsumerState<_ApplicationsCard> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final lookups = widget.lookups;
    final controller = ref.read(masterDataProvider.notifier);
    final fmt = DateFormat('MMM dd, yyyy');

    Widget pill(String? status) {
      final text = (status ?? '').trim();
      if (text.isEmpty) return const Text('—', style: AppTypography.body);
      final pal = statusPaletteFor(text);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: pal.background, borderRadius: AppRadius.pillAll),
        child: Text(text, style: AppTypography.chip.copyWith(color: pal.ink)),
      );
    }

    Widget clipped(String? text) => Text(text ?? '—',
        style: AppTypography.body, maxLines: 1, overflow: TextOverflow.ellipsis);

    Widget cell(Widget child, int flex) => Expanded(flex: flex, child: child);

    final statusSuggestions = ref.watch(statusNamesProvider);

    Future<void> edit(int index) async {
      final updated = await showApplicationEditor(context,
          lookups: lookups,
          existing: draft.applications[index],
          statusSuggestions: statusSuggestions);
      if (updated != null) {
        setState(() => draft.applications[index] = updated);
        controller.touch();
      }
    }

    // No SectionCard of its own — this is the right-hand column of the
    // combined Applications/PIC & Notes card built by
    // _ApplicationsSectionCard, which supplies the shared title/border.
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add application'),
              onPressed: () async {
                final row = await showApplicationEditor(context,
                    lookups: lookups, statusSuggestions: statusSuggestions);
                if (row != null) {
                  setState(() => draft.applications.insert(0, row));
                  controller.touch();
                }
              },
            ),
            const Spacer(),
            // One-off PDFs for this applicant, as in the old toolbar.
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline, size: 15),
              label: const Text('Letter'),
              onPressed: draft.isNew
                  ? null
                  : () => _openApplicantPdf(context, ref,
                      '/api/reports/letter/${draft.id}', 'letter.pdf'),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined, size: 15),
              label: const Text('Resume'),
              onPressed: draft.isNew
                  ? null
                  : () => _openApplicantPdf(context, ref,
                      '/api/reports/resume/${draft.id}', 'resume.pdf'),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.badge_outlined, size: 15),
              label: const Text('Card'),
              onPressed: draft.isNew
                  ? null
                  : () => _openApplicantPdf(context, ref,
                      '/api/reports/card/${draft.id}', 'card.pdf'),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (draft.applications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No applications recorded for this person yet.',
                  style: AppTypography.helper),
            )
          else
            ClipRRect(
              borderRadius: AppRadius.smAll,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: AppRadius.smAll,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: AppColors.surface2,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          for (var c = 0; c < _ApplicationsCard._headers.length; c++)
                            cell(
                              Text(_ApplicationsCard._headers[c],
                                  style: AppTypography.tableHeader),
                              _ApplicationsCard._colFlex[c],
                            ),
                        ],
                      ),
                    ),
                    for (final (i, a) in draft.applications.indexed)
                      InkWell(
                        onTap: () => edit(i),
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: AppColors.line)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              cell(
                                  clipped(a.appDate == null
                                      ? '—'
                                      : fmt.format(a.appDate!)),
                                  _ApplicationsCard._colFlex[0]),
                              cell(clipped(a.position), _ApplicationsCard._colFlex[1]),
                              cell(clipped(a.department), _ApplicationsCard._colFlex[2]),
                              cell(pill(a.status), _ApplicationsCard._colFlex[3]),
                              cell(clipped(a.empStatus), _ApplicationsCard._colFlex[4]),
                              cell(
                                  clipped(a.intvwDate == null
                                      ? '—'
                                      : fmt.format(a.intvwDate!)),
                                  _ApplicationsCard._colFlex[5]),
                              cell(clipped(a.recommendation), _ApplicationsCard._colFlex[6]),
                              cell(
                                  clipped(a.hiredDate == null
                                      ? '—'
                                      : fmt.format(a.hiredDate!)),
                                  _ApplicationsCard._colFlex[7]),
                              cell(pill(a.finalStatus), _ApplicationsCard._colFlex[8]),
                              cell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      style: AppButtonStyles.tableActionEdit,
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      iconSize: 16,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Edit',
                                      onPressed: () => edit(i),
                                    ),
                                    const SizedBox(width: 2),
                                    IconButton(
                                      style: AppButtonStyles.tableActionDelete,
                                      icon: const Icon(Icons.delete_outline, size: 16),
                                      iconSize: 16,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Remove',
                                      onPressed: () async {
                                        final ok = await confirmDialog(
                                          context,
                                          title: 'Remove this application?',
                                          message:
                                              'This application row will be deleted when you save the record.',
                                          confirmLabel: 'Remove',
                                        );
                                        if (ok) {
                                          setState(() => draft.applications.removeAt(i));
                                          controller.touch();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                _ApplicationsCard._colFlex[9],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
  }
}

// ============ Section 5: person-in-charge & notes ============

class _PicNotesCard extends ConsumerStatefulWidget {
  const _PicNotesCard({required this.draft, required this.lookups});
  final MasterDataDraft draft;
  final Lookups lookups;

  @override
  ConsumerState<_PicNotesCard> createState() => _PicNotesCardState();
}

class _PicNotesCardState extends ConsumerState<_PicNotesCard> {
  late final TextEditingController _notes =
      TextEditingController(text: widget.draft.notes);

  @override
  void didUpdateWidget(_PicNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      _notes.text = widget.draft.notes;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final controller = ref.read(masterDataProvider.notifier);
    final staff = widget.lookups.staff;

    // No SectionCard of its own — this is the fixed-width left column of
    // the combined card built by _ApplicationsSectionCard, stacked vertically
    // since 220px is too narrow for the dropdown and notes side by side.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PIC & NOTES', style: AppTypography.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        Labeled(
          label: 'Person-in-charge',
          required: true,
          child: SearchableDropdown(
            options: staff,
            value: d.personincharge,
            allowClear: false,
            onChanged: (v) {
              d.personincharge = v;
              controller.touch();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Labeled(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _nextField(context),
            style: kValueStyle,
            maxLines: 5,
            minLines: 4,
            onChanged: (v) {
              d.notes = v;
              controller.touch();
            },
          ),
        ),
      ],
    );
  }
}

// ============ Combined Applications + PIC & Notes card ============

/// Wraps [_PicNotesCard] (fixed-width left column, right-border divider) and
/// [_ApplicationsCard] (flexible right column) in one SectionCard, per the
/// redesign's combined-card layout.
class _ApplicationsSectionCard extends StatelessWidget {
  const _ApplicationsSectionCard({required this.draft, required this.lookups});
  final MasterDataDraft draft;
  final Lookups lookups;

  static const _picColumnWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Applications',
      // See _EqualHeightPair for why this isn't a plain IntrinsicHeight —
      // it also gives the divider a full-height look regardless of which
      // column (PIC & Notes vs. the table) is naturally taller.
      child: _EqualHeightPair(
        leftWidth: _picColumnWidth,
        left: Container(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          child: _PicNotesCard(draft: draft, lookups: lookups),
        ),
        right: _ApplicationsCard(draft: draft, lookups: lookups),
      ),
    );
  }
}

/// Keeps two side-by-side widgets visually the same height without
/// [IntrinsicHeight] — several fields on this page are [SearchableDropdown],
/// whose internal [LayoutBuilder] throws "does not support returning
/// intrinsic dimensions" the moment anything above it asks for an intrinsic
/// size. Instead, this measures each side's rendered height after every
/// frame and applies the taller one as a *minimum* height (never a cap) on
/// both, so a side can still grow past the last-measured height (more
/// eligibility chips, a longer note) without ever being clipped.
class _EqualHeightPair extends StatefulWidget {
  const _EqualHeightPair({required this.left, required this.right, this.leftWidth});

  final Widget left;
  final Widget right;

  /// Fixed width for the left side; if null, left and right split the row
  /// evenly (both `Expanded`).
  final double? leftWidth;

  @override
  State<_EqualHeightPair> createState() => _EqualHeightPairState();
}

class _EqualHeightPairState extends State<_EqualHeightPair> {
  final _leftKey = GlobalKey();
  final _rightKey = GlobalKey();
  double? _minHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void didUpdateWidget(_EqualHeightPair oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final lh = (_leftKey.currentContext?.findRenderObject() as RenderBox?)?.size.height;
    final rh = (_rightKey.currentContext?.findRenderObject() as RenderBox?)?.size.height;
    if (lh == null || rh == null) return;
    final tallest = lh > rh ? lh : rh;
    if (tallest > 0 && tallest != _minHeight) {
      setState(() => _minHeight = tallest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = _minHeight ?? 0;
    Widget floor(Widget child, GlobalKey key) => ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: KeyedSubtree(key: key, child: child),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.leftWidth != null
            ? SizedBox(
                width: widget.leftWidth,
                child: floor(widget.left, _leftKey),
              )
            : Expanded(child: floor(widget.left, _leftKey)),
        const SizedBox(width: _cardGap),
        Expanded(child: floor(widget.right, _rightKey)),
      ],
    );
  }
}
