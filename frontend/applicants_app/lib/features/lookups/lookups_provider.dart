import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_provider.dart';

// Lookups back largely-static dropdown data (provinces, municipals,
// departments, education, eligibilities, recommendation officers, staff,
// schools) that only changes via a Settings save or quick-add — both of
// which already call [clearLookupsCache] before invalidating this provider.
// Persisting the raw fetch to disk means a normal app restart doesn't have
// to repeat the 9-endpoint fan-out below just to redraw dropdowns that
// haven't changed.
const _cacheKey = 'lookups-cache-v1';
const _cacheTtl = Duration(hours: 12);

Future<void> clearLookupsCache() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_cacheKey);
}

class MunicipalRow {
  const MunicipalRow(this.id, this.municipal, this.district, this.provinceId);
  final int id;
  final String municipal;
  final String? district;
  final int? provinceId;
}

class ProvinceRow {
  const ProvinceRow(this.id, this.province, this.region);
  final int id;
  final String province;
  final String? region;
}

class OfficerRow {
  const OfficerRow(this.id, this.recommending, this.designation);
  final int id;
  final String recommending;
  final String? designation;
}

/// All seven lookup tables in one cached fetch — shared by Master Data
/// dropdowns now and the Settings screen later.
class Lookups {
  const Lookups({
    required this.provinces,
    required this.municipals,
    required this.departments,
    required this.education,
    required this.eligibilities,
    required this.officers,
    required this.staff,
    required this.schools,
    this.municipalUsage = const {},
    this.municipalsMostUsedFirst = const [],
  });

  final List<ProvinceRow> provinces;
  final List<MunicipalRow> municipals;
  final List<String> departments;
  final List<String> education;
  final List<String> eligibilities;
  final List<OfficerRow> officers;
  final List<String> staff;

  /// "School graduated from" — distinct from `education` (the course).
  final List<String> schools;

  /// Trimmed municipality name → how many active applicants carry it.
  final Map<String, int> municipalUsage;

  /// Municipality names for the address dropdown, most-used first (ties and
  /// unused names alphabetical) — Lingayen shouldn't hide 30 items down.
  /// Computed once in [_buildLookups] rather than re-sorted on every read —
  /// this used to be a getter re-sorting the full list on every Master Data
  /// Address card build.
  final List<String> municipalsMostUsedFirst;

  ProvinceRow? provinceOf(MunicipalRow muni) {
    if (muni.provinceId == null) return null;
    for (final p in provinces) {
      if (p.id == muni.provinceId) return p;
    }
    return null;
  }

  MunicipalRow? municipalByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final probe = name.trim().toLowerCase();
    for (final m in municipals) {
      if (m.municipal.trim().toLowerCase() == probe) return m;
    }
    return null;
  }

  ProvinceRow? provinceByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final probe = name.trim().toLowerCase();
    for (final p in provinces) {
      if (p.province.trim().toLowerCase() == probe) return p;
    }
    return null;
  }

  List<String> municipalsForProvince(String? provinceName) {
    final p = provinceByName(provinceName);
    if (p == null) return municipalsMostUsedFirst;
    final filtered = municipals
        .where((m) => m.provinceId == p.id)
        .map((m) => m.municipal)
        .toList()
      ..sort((a, b) {
        final ua = municipalUsage[a.trim()] ?? 0;
        final ub = municipalUsage[b.trim()] ?? 0;
        if (ua != ub) return ub.compareTo(ua);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return filtered.isEmpty ? municipalsMostUsedFirst : filtered;
  }
}

final lookupsProvider = FutureProvider<Lookups>((ref) async {
  final prefs = await SharedPreferences.getInstance();

  final cachedRaw = prefs.getString(_cacheKey);
  if (cachedRaw != null) {
    try {
      final cached = jsonDecode(cachedRaw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(cached['cachedAt'] as String);
      if (DateTime.now().difference(cachedAt) < _cacheTtl) {
        return _buildLookups(cached['results'] as List);
      }
    } catch (_) {
      // Unreadable/old-shape cache entry — fall through and refetch.
    }
  }

  final api = ref.read(apiClientProvider);
  final results = await Future.wait([
    api.get('/api/lookups/provinces'),
    api.get('/api/lookups/municipals'),
    api.get('/api/lookups/departments'),
    api.get('/api/lookups/education'),
    api.get('/api/lookups/eligibilities'),
    api.get('/api/lookups/recommendation'),
    api.get('/api/lookups/staff'),
    api.get('/api/lookups/municipals/usage'),
    api.get('/api/lookups/schools'),
  ]);

  await prefs.setString(
      _cacheKey,
      jsonEncode({
        'cachedAt': DateTime.now().toIso8601String(),
        'results': results,
      }));

  return _buildLookups(results);
});

Lookups _buildLookups(List results) {
  List<String> values(dynamic list) => (list as List)
      .map((e) => (e['value'] as String?) ?? '')
      .where((s) => s.trim().isNotEmpty)
      .toList();

  final municipals = (results[1] as List)
      .map((e) => MunicipalRow(e['id'] as int, (e['municipal'] as String?) ?? '',
          e['district'] as String?, e['provinceId'] as int?))
      .where((m) => m.municipal.trim().isNotEmpty)
      .toList();
  final municipalUsage = {
    for (final e in results[7] as List)
      ((e['municipal'] as String?) ?? '').trim(): (e['uses'] as int?) ?? 0,
  };
  final municipalsMostUsedFirst = municipals.map((m) => m.municipal).toList()
    ..sort((a, b) {
      final ua = municipalUsage[a.trim()] ?? 0;
      final ub = municipalUsage[b.trim()] ?? 0;
      if (ua != ub) return ub.compareTo(ua);
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return Lookups(
    provinces: (results[0] as List)
        .map((e) => ProvinceRow(
            e['id'] as int, (e['province'] as String?) ?? '', e['region'] as String?))
        .where((p) => p.province.trim().isNotEmpty)
        // The table carries a literal "Select..." placeholder row from the
        // legacy app — keep it out of the dropdown.
        .where((p) => p.province.trim().toLowerCase() != 'select...')
        .toList(),
    municipals: municipals,
    departments: values(results[2]),
    education: values(results[3]),
    eligibilities: values(results[4]),
    officers: (results[5] as List)
        .map((e) => OfficerRow(e['id'] as int,
            (e['recommending'] as String?) ?? '', e['designation'] as String?))
        .where((o) => o.recommending.trim().isNotEmpty)
        .toList(),
    staff: values(results[6]),
    municipalUsage: municipalUsage,
    schools: values(results[8]),
    municipalsMostUsedFirst: municipalsMostUsedFirst,
  );
}
