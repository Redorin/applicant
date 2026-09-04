import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/master_data.dart';

/// Values carried from the last saved NEW applicant into the next blank
/// draft — applicants arrive in batches sharing municipality, so the
/// encoder shouldn't re-type them.
class StickyFields {
  const StickyFields({
    this.municipality,
    this.province,
    this.district,
    this.gender,
    this.civistat,
  });

  factory StickyFields.fromJson(Map<String, dynamic> json) => StickyFields(
        municipality: json['municipality'] as String?,
        province: json['province'] as String?,
        district: json['district'] as String?,
        gender: json['gender'] as String?,
        civistat: json['civistat'] as String?,
      );

  final String? municipality;
  final String? province;
  final String? district;
  final String? gender;
  final String? civistat;

  bool get isEmpty => (municipality ?? '').isEmpty;

  /// Short human label for the carried-over chip in the action bar.
  String get summary {
    final parts = <String>[
      if ((municipality ?? '').isNotEmpty) municipality!,
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'municipality': municipality,
        'province': province,
        'district': district,
        'gender': gender,
        'civistat': civistat,
      };
}

class StickyFieldsController extends Notifier<StickyFields?> {
  static const _prefsKey = 'sticky-fields';

  @override
  StickyFields? build() {
    // Prefs are async; hydrate shortly after startup. Until then stickies
    // simply don't apply, which is harmless.
    Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || state != null) return;
      try {
        state = StickyFields.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        await prefs.remove(_prefsKey);
      }
    });
    return null;
  }

  /// Remember the batch-shaped values of a just-saved new applicant.
  void capture(MasterDataDraft d) {
    final sticky = StickyFields(
      municipality: d.municipality,
      province: d.province,
      district: d.district,
      gender: d.gender,
      civistat: d.civistat,
    );
    state = sticky.isEmpty ? null : sticky;
    _persist();
  }

  void clear() {
    state = null;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final s = state;
    if (s == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    }
  }
}

final stickyFieldsProvider =
    NotifierProvider<StickyFieldsController, StickyFields?>(
        StickyFieldsController.new);
