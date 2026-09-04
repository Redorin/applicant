import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/text/name_case.dart';
import '../../models/master_data.dart';
import '../auth/auth_provider.dart';
import '../shell/toast_provider.dart';
import 'recently_opened_provider.dart';
import 'sticky_fields.dart';

/// Default province for new records — HRMDO serves Pangasinan.
const kDefaultProvince = 'Pangasinan';

/// How much of a possible duplicate we can assert: nothing, a same-name match
/// (birthdate not entered yet), or a same-name-and-birthdate match.
enum DuplicateWarning { none, nameOnly, nameAndBirth }

class MasterDataState {
  const MasterDataState({
    this.draft,
    this.searchResults = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.validationErrors = const [],
    this.duplicateWarning = DuplicateWarning.none,
    this.duplicateMatches = const [],
    this.dirty = false,
    this.epoch = 0,
    this.stickiesApplied = false,
  });

  /// The record being viewed/edited; null until one is loaded or created.
  final MasterDataDraft? draft;
  final List<SearchRow> searchResults;
  final bool isLoading;
  final bool isSaving;
  final List<String> validationErrors;
  final DuplicateWarning duplicateWarning;

  /// The actual matching record(s) behind [duplicateWarning] — populated
  /// alongside it so [DuplicateWarningBanner] can show who they are (avatar,
  /// name, municipality), not just that a match exists.
  final List<SearchRow> duplicateMatches;
  final bool dirty;

  /// Bumped on every load/new — feeds this state's equality override so
  /// Riverpod still sees a change even when the record id stays the same
  /// (e.g. one blank draft replacing another after New Applicant).
  final int epoch;

  /// True when the current (still-pristine) new draft was pre-filled from
  /// the previous save — drives the "Carried over" chip in the action bar.
  final bool stickiesApplied;

  MasterDataState copyWith({
    MasterDataDraft? draft,
    bool clearDraft = false,
    List<SearchRow>? searchResults,
    bool? isLoading,
    bool? isSaving,
    List<String>? validationErrors,
    DuplicateWarning? duplicateWarning,
    List<SearchRow>? duplicateMatches,
    bool? dirty,
    int? epoch,
    bool? stickiesApplied,
  }) =>
      MasterDataState(
        draft: clearDraft ? null : (draft ?? this.draft),
        searchResults: searchResults ?? this.searchResults,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        validationErrors: validationErrors ?? this.validationErrors,
        duplicateWarning: duplicateWarning ?? this.duplicateWarning,
        duplicateMatches: duplicateMatches ?? this.duplicateMatches,
        dirty: dirty ?? this.dirty,
        epoch: epoch ?? this.epoch,
        stickiesApplied: stickiesApplied ?? this.stickiesApplied,
      );

  // `draft` is mutated in place by the form (see touch() below) rather than
  // replaced, so reference identity is exactly the right comparison: it's
  // unchanged across a `touch()` that only re-affirms dirty=true, and it's a
  // new instance whenever load()/newApplicant()/discardDraft() actually swap
  // in a different record. Same reasoning for searchResults/validationErrors,
  // which are always replaced wholesale (never mutated) when they change.
  // Without this override every touch() produced a distinct MasterDataState
  // (default identity equality), so Riverpod's `previous != next` notified
  // on every keystroke in the form, rebuilding all five section cards.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MasterDataState &&
          identical(draft, other.draft) &&
          identical(searchResults, other.searchResults) &&
          identical(validationErrors, other.validationErrors) &&
          identical(duplicateMatches, other.duplicateMatches) &&
          isLoading == other.isLoading &&
          isSaving == other.isSaving &&
          duplicateWarning == other.duplicateWarning &&
          dirty == other.dirty &&
          epoch == other.epoch &&
          stickiesApplied == other.stickiesApplied);

  @override
  int get hashCode => Object.hash(
      draft,
      searchResults,
      validationErrors,
      duplicateMatches,
      isLoading,
      isSaving,
      duplicateWarning,
      dirty,
      epoch,
      stickiesApplied);
}

/// What a crash left behind: enough to offer "Recover unsaved work?".
class AutosaveInfo {
  const AutosaveInfo({required this.displayName, required this.savedAt});
  final String displayName;
  final DateTime savedAt;
}

class MasterDataController extends Notifier<MasterDataState> {
  static const _autosaveKey = 'draft-autosave';

  ApiClient get _api => ref.read(apiClientProvider);

  Timer? _dupDebounce;
  Timer? _autosaveTimer;

  // A freshly picked photo that hasn't been uploaded yet — held here (not in
  // MasterDataState/autosave) since it's transient UI state, not part of the
  // record until _persist() actually uploads it after a successful save.
  Uint8List? _pendingPhotoBytes;
  String? _pendingPhotoName;

  @override
  MasterDataState build() {
    ref.onDispose(() {
      _dupDebounce?.cancel();
      _autosaveTimer?.cancel();
    });
    return const MasterDataState();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    final json = await _api
        .get('/api/masterdata/?search=${Uri.encodeComponent(query.trim())}&limit=30');
    state = state.copyWith(
      searchResults: (json as List)
          .map((e) => SearchRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  void clearSearch() => state = state.copyWith(searchResults: []);

  Future<void> load(int id) async {
    // Reaching here means the unsaved guard already resolved any dirty
    // draft, so a leftover autosave is stale.
    await clearAutosave();
    state = state.copyWith(isLoading: true, searchResults: []);
    try {
      final json = await _api.get('/api/masterdata/$id');
      final loaded = MasterDataDraft.fromJson(json as Map<String, dynamic>);
      state = state.copyWith(
        draft: loaded,
        isLoading: false,
        validationErrors: [],
        duplicateWarning: DuplicateWarning.none,
        duplicateMatches: [],
        dirty: false,
        epoch: state.epoch + 1,
        stickiesApplied: false,
      );
      ref
          .read(recentlyOpenedProvider.notifier)
          .record(id, '${loaded.surname}, ${loaded.firstname}');
    } catch (_) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  void newApplicant() {
    // Same post-guard reasoning as load(): any autosave is now stale.
    clearAutosave();
    final draft = MasterDataDraft();
    var applied = false;

    // Batch entry: carry municipality/etc. from the last saved
    // new applicant.
    final sticky = ref.read(stickyFieldsProvider);
    if (sticky != null) {
      if ((sticky.municipality ?? '').isNotEmpty) {
        draft.municipality = sticky.municipality;
        draft.province = sticky.province;
        draft.district = sticky.district ?? '';
        applied = true;
      }
      if ((sticky.gender ?? '').isNotEmpty) {
        draft.gender = sticky.gender;
        applied = true;
      }
      if ((sticky.civistat ?? '').isNotEmpty) {
        draft.civistat = sticky.civistat;
        applied = true;
      }
    }
    if ((draft.province ?? '').isEmpty) draft.province = kDefaultProvince;

    state = state.copyWith(
      draft: draft,
      validationErrors: [],
      duplicateWarning: DuplicateWarning.none,
      duplicateMatches: [],
      dirty: false,
      epoch: state.epoch + 1,
      stickiesApplied: applied,
    );
  }

  /// Throw away the current draft and its edits entirely — the "Discard
  /// changes" outcome of the unsaved guard. Without this, navigating away
  /// left the dirty draft (and its autosave) in place and the guard kept
  /// re-prompting forever.
  void discardDraft() {
    clearAutosave();
    state = state.copyWith(
      clearDraft: true,
      validationErrors: [],
      duplicateWarning: DuplicateWarning.none,
      duplicateMatches: [],
      dirty: false,
      epoch: state.epoch + 1,
      stickiesApplied: false,
    );
  }

  /// The draft object is mutated in place by the form; call this to rebuild.
  /// Every edit also (re)arms a 2s autosave so a crash can't eat a record.
  void touch() {
    state = state.copyWith(dirty: true);
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), _writeAutosave);
  }

  // ---------- crash-recovery autosave ----------

  Future<void> _writeAutosave() async {
    final d = state.draft;
    if (d == null || !state.dirty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _autosaveKey,
        jsonEncode({
          'draft': d.toJson(),
          'savedAt': DateTime.now().toIso8601String(),
        }));
  }

  /// Dropped whenever the draft reaches a resolved state: saved, replaced
  /// via the unsaved guard, or explicitly discarded from the recovery dialog.
  Future<void> clearAutosave() async {
    _autosaveTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_autosaveKey);
  }

  /// Non-destructive look at a leftover autosave, if any.
  Future<AutosaveInfo?> peekAutosave() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autosaveKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final d =
          MasterDataDraft.fromJson(map['draft'] as Map<String, dynamic>);
      final name = [
        if (d.surname.trim().isNotEmpty) d.surname.trim(),
        if (d.firstname.trim().isNotEmpty) d.firstname.trim(),
      ].join(', ');
      return AutosaveInfo(
        displayName: name.isEmpty ? '(no name yet)' : name,
        savedAt: DateTime.tryParse((map['savedAt'] as String?) ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      await prefs.remove(_autosaveKey);
      return null;
    }
  }

  /// Puts the autosaved draft back on screen, marked dirty so the unsaved
  /// guard protects it again.
  Future<bool> restoreAutosave() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_autosaveKey);
    if (raw == null) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final d =
          MasterDataDraft.fromJson(map['draft'] as Map<String, dynamic>);
      state = state.copyWith(
        draft: d,
        validationErrors: [],
        duplicateWarning: DuplicateWarning.none,
        duplicateMatches: [],
        dirty: true,
        epoch: state.epoch + 1,
        stickiesApplied: false,
      );
      return true;
    } catch (_) {
      await prefs.remove(_autosaveKey);
      return false;
    }
  }

  /// Guards on 3+ characters in both names (rather than merely non-empty) —
  /// the deliberate threshold the duplicate banner asks for, so the warning
  /// doesn't fire on a single keystroke.
  Future<void> checkDuplicate() async {
    final d = state.draft;
    if (d == null || d.surname.trim().length < 3 || d.firstname.trim().length < 3) {
      state = state.copyWith(duplicateWarning: DuplicateWarning.none, duplicateMatches: []);
      return;
    }
    final dbirth = d.dbirth;
    try {
      final json = await _api.get(
          '/api/masterdata/duplicate-check?surname=${Uri.encodeComponent(d.surname.trim())}'
          '&firstname=${Uri.encodeComponent(d.firstname.trim())}'
          '${dbirth == null ? '' : '&dbirth=${dbirth.toIso8601String()}'}'
          '&excludeId=${d.id ?? -1}');
      final found = (json['count'] as int) > 0;
      if (!found) {
        state = state.copyWith(
            duplicateWarning: DuplicateWarning.none, duplicateMatches: []);
        return;
      }
      final matches = await _fetchDuplicateMatches(
        surname: d.surname.trim(),
        firstname: d.firstname.trim(),
        dbirth: dbirth,
        excludeId: d.id,
      );
      state = state.copyWith(
        duplicateWarning:
            dbirth == null ? DuplicateWarning.nameOnly : DuplicateWarning.nameAndBirth,
        duplicateMatches: matches,
      );
    } catch (_) {
      // Advisory only — never block on a failed duplicate probe.
    }
  }

  /// The backend's /duplicate-check endpoint only returns a count — reuse
  /// the existing live-search endpoint (already returns full SearchRow
  /// objects) to get the actual matching record(s) for the banner, filtering
  /// client-side for an exact name (+ same-day birthdate, when entered)
  /// match. Advisory only, same as checkDuplicate() itself — any failure
  /// here just means an empty match list, never a thrown error.
  Future<List<SearchRow>> _fetchDuplicateMatches({
    required String surname,
    required String firstname,
    DateTime? dbirth,
    int? excludeId,
  }) async {
    try {
      final json =
          await _api.get('/api/masterdata/?search=${Uri.encodeComponent(surname)}&limit=30');
      return (json as List)
          .map((e) => SearchRow.fromJson(e as Map<String, dynamic>))
          .where((r) =>
              r.id != excludeId &&
              r.surname.trim().toLowerCase() == surname.toLowerCase() &&
              r.firstname.trim().toLowerCase() == firstname.toLowerCase() &&
              (dbirth == null ||
                  (r.dbirth != null &&
                      r.dbirth!.year == dbirth.year &&
                      r.dbirth!.month == dbirth.month &&
                      r.dbirth!.day == dbirth.day)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Debounced variant for the surname/firstname onChanged handlers, so the
  /// warning appears while the encoder is still typing without spamming the API.
  void checkDuplicateDebounced() {
    _dupDebounce?.cancel();
    _dupDebounce =
        Timer(const Duration(milliseconds: 500), () => checkDuplicate());
  }

  /// "Continue anyway" on the duplicate banner — a purely client-side
  /// dismissal (no backend call), since the check is advisory only.
  void dismissDuplicateWarning() =>
      state = state.copyWith(duplicateWarning: DuplicateWarning.none, duplicateMatches: []);

  /// Opens the file picker for a 1x1 photo and returns the picked bytes for
  /// the caller to preview immediately (the upload itself waits for the next
  /// save, in _persist()). Returns null if the user cancelled or the file
  /// failed validation.
  Future<Uint8List?> pickPhoto() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Image', extensions: ['jpg', 'jpeg', 'png']),
    ]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      ref.read(toastProvider.notifier).show('Photo must be under 2MB.');
      return null;
    }
    _pendingPhotoBytes = bytes;
    _pendingPhotoName = file.name;
    state = state.copyWith(dirty: true);
    return bytes;
  }

  /// Bytes for the already-saved photo, for the preview box to display.
  Future<Uint8List> fetchPhoto(int id) => _api.getBytes('/api/masterdata/$id/photo');

  /// Removes the saved photo immediately (unlike upload, this isn't deferred
  /// to save — there's nothing to lose by acting right away).
  Future<void> deletePhoto() async {
    final d = state.draft;
    if (d == null || d.isNew) return;
    await _api.delete('/api/masterdata/${d.id}/photo');
    d.photoPath = null;
    _pendingPhotoBytes = null;
    _pendingPhotoName = null;
    state = state.copyWith(dirty: true);
  }

  /// Shared save core: normalize, POST/PUT, capture stickies. Returns the
  /// saved id. On failure (incl. 422 validation) resets isSaving and rethrows
  /// so callers can show the dialog/toast.
  Future<int> _persist() async {
    final d = state.draft!;
    state = state.copyWith(isSaving: true, validationErrors: []);
    try {
      // One choke point for tidy data: Title Case names, trim everything.
      normalizeDraftForSave(d);
      final wasNew = d.isNew;
      final body = d.toJson();
      final res = wasNew
          ? await _api.post('/api/masterdata/', body: body)
          : await _api.put('/api/masterdata/${d.id}', body: body);
      final savedId = res['id'] as int;
      if (_pendingPhotoBytes != null) {
        await _api.uploadPhoto('/api/masterdata/$savedId/photo',
            _pendingPhotoBytes!, _pendingPhotoName!);
        _pendingPhotoBytes = null;
        _pendingPhotoName = null;
      }
      // A freshly entered applicant defines the batch shape for the next one.
      if (wasNew) {
        ref.read(stickyFieldsProvider.notifier).capture(d);
        ref.read(encodedTodayProvider.notifier).increment();
      }
      ref
          .read(recentlyOpenedProvider.notifier)
          .record(savedId, '${d.surname}, ${d.firstname}');
      await clearAutosave();
      return savedId;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  /// Returns true when saved; on 422 fills validationErrors for the dialog.
  Future<bool> save() async {
    if (state.draft == null) return false;
    final savedId = await _persist();
    await load(savedId);
    state = state.copyWith(isSaving: false);
    return true;
  }

  Future<void> archive() async {
    final d = state.draft;
    if (d == null || d.isNew) return;
    await _api.post('/api/masterdata/${d.id}/archive');
    state = state.copyWith(clearDraft: true, dirty: false);
  }

  void setValidationErrors(List<String> errors) =>
      state = state.copyWith(validationErrors: errors);
}

final masterDataProvider =
    NotifierProvider<MasterDataController, MasterDataState>(
        MasterDataController.new);
