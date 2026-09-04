/// DTOs matching the backend's MasterData feature JSON shapes.
library;

import 'dart:convert';

import 'package:intl/intl.dart';

class ApplicationRow {
  ApplicationRow({
    this.id,
    this.appDate,
    this.position,
    this.department,
    this.status,
    this.intvwDate,
    this.recommendation,
    this.hiredDate,
    this.finalPosition,
    this.finalDepartment,
    this.finalStatus,
    this.empStatus,
    this.remarks,
    this.assumption,
  });

  factory ApplicationRow.fromJson(Map<String, dynamic> json) {
    DateTime? d(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return ApplicationRow(
      id: json['id'] as int?,
      appDate: d('appDate'),
      position: json['position'] as String?,
      department: json['department'] as String?,
      status: json['status'] as String?,
      intvwDate: d('intvwDate'),
      recommendation: json['recommendation'] as String?,
      hiredDate: d('hiredDate'),
      finalPosition: json['finalPosition'] as String?,
      finalDepartment: json['finalDepartment'] as String?,
      finalStatus: json['finalStatus'] as String?,
      empStatus: json['empStatus'] as String?,
      remarks: json['remarks'] as String?,
      assumption: d('assumption'),
    );
  }

  int? id;
  DateTime? appDate;
  String? position;
  String? department;
  String? status;
  DateTime? intvwDate;
  String? recommendation;
  DateTime? hiredDate;
  String? finalPosition;
  String? finalDepartment;
  String? finalStatus;
  String? empStatus;
  String? remarks;
  DateTime? assumption;

  Map<String, dynamic> toJson() => {
        'id': id,
        'appDate': appDate?.toIso8601String(),
        'position': position,
        'department': department,
        'status': status,
        'intvwDate': intvwDate?.toIso8601String(),
        'recommendation': recommendation,
        'hiredDate': hiredDate?.toIso8601String(),
        'finalPosition': finalPosition,
        'finalDepartment': finalDepartment,
        'finalStatus': finalStatus,
        'empStatus': empStatus,
        'remarks': remarks,
        'assumption': assumption?.toIso8601String(),
      };
}

class MasterDataDraft {
  MasterDataDraft({
    this.id,
    this.surname = '',
    this.firstname = '',
    this.midname = '',
    this.ext = '',
    this.dbirth,
    this.gender,
    this.civistat,
    this.contact = '',
    this.contact2 = '',
    this.address = '',
    this.houseNo = '',
    this.street = '',
    this.subdivision = '',
    this.barangay = '',
    this.municipality,
    this.district = '',
    this.province,
    this.education,
    this.education2,
    this.school,
    this.legacyEligibility,
    this.experience = '',
    this.skills = '',
    this.personincharge,
    this.notes = '',
    this.lenofservice = '',
    this.training = '',
    this.photoPath,
    List<String>? eligibilities,
    List<ApplicationRow>? applications,
  })  : eligibilities = eligibilities ?? [],
        applications = applications ?? [];

  factory MasterDataDraft.fromJson(Map<String, dynamic> json) {
    return MasterDataDraft(
      id: json['id'] as int?,
      surname: (json['surname'] as String?) ?? '',
      firstname: (json['firstname'] as String?) ?? '',
      midname: (json['midname'] as String?) ?? '',
      ext: (json['ext'] as String?) ?? '',
      dbirth: json['dbirth'] == null
          ? null
          : DateTime.parse(json['dbirth'] as String),
      gender: json['gender'] as String?,
      civistat: json['civistat'] as String?,
      contact: (json['contact'] as String?) ?? '',
      contact2: (json['contact2'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      houseNo: (json['houseNo'] as String?) ?? '',
      street: (json['street'] as String?) ?? '',
      subdivision: (json['subdivision'] as String?) ?? '',
      barangay: (json['barangay'] as String?) ?? '',
      municipality: json['municipality'] as String?,
      district: (json['district'] as String?) ?? '',
      province: json['province'] as String?,
      education: json['education'] as String?,
      education2: json['education2'] as String?,
      school: json['school'] as String?,
      legacyEligibility: json['legacyEligibility'] as String?,
      experience: (json['experience'] as String?) ?? '',
      skills: (json['skills'] as String?) ?? '',
      personincharge: json['personincharge'] as String?,
      notes: (json['notes'] as String?) ?? '',
      lenofservice: (json['lenofservice'] as String?) ?? '',
      training: (json['training'] as String?) ?? '',
      photoPath: json['photoPath'] as String?,
      eligibilities:
          ((json['eligibilities'] as List?) ?? []).cast<String>().toList(),
      applications: ((json['applications'] as List?) ?? [])
          .map((e) => ApplicationRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  int? id;
  String surname;
  String firstname;
  String midname;
  String ext;
  DateTime? dbirth;
  String? gender;
  String? civistat;
  String contact;
  String contact2;
  String address;
  String houseNo;
  String street;
  String subdivision;
  String barangay;
  String? municipality;
  String district;
  String? province;
  String? education;
  String? education2;
  String? school;
  String? legacyEligibility;
  String experience;
  String skills;
  String? personincharge;
  String notes;
  String lenofservice;
  String training;
  String? photoPath;
  List<String> eligibilities;
  List<ApplicationRow> applications;

  bool get isNew => id == null || id == 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'surname': surname,
        'firstname': firstname,
        'midname': midname,
        'ext': ext,
        'dbirth': dbirth?.toIso8601String(),
        'gender': gender,
        'civistat': civistat,
        'contact': contact,
        'contact2': contact2,
        'address': address,
        'houseNo': houseNo,
        'street': street,
        'subdivision': subdivision,
        'barangay': barangay,
        'municipality': municipality,
        'district': district,
        'province': province,
        'education': education,
        'education2': education2,
        'school': school,
        'legacyEligibility': legacyEligibility,
        'experience': experience,
        'skills': skills,
        'personincharge': personincharge,
        'notes': notes,
        'lenofservice': lenofservice,
        'training': training,
        'photoPath': photoPath,
        'eligibilities': eligibilities,
        'applications': applications.map((a) => a.toJson()).toList(),
      };
}

class SearchRow {
  const SearchRow({
    required this.id,
    required this.surname,
    required this.firstname,
    this.midname,
    this.municipality,
    this.dbirth,
    this.latestStatus,
  });

  factory SearchRow.fromJson(Map<String, dynamic> json) => SearchRow(
        id: json['id'] as int,
        surname: (json['surname'] as String?) ?? '',
        firstname: (json['firstname'] as String?) ?? '',
        midname: json['midname'] as String?,
        municipality: json['municipality'] as String?,
        dbirth: json['dbirth'] == null
            ? null
            : DateTime.parse(json['dbirth'] as String),
        latestStatus: json['latestStatus'] as String?,
      );

  final int id;
  final String surname;
  final String firstname;
  final String? midname;
  final String? municipality;
  final DateTime? dbirth;
  final String? latestStatus;

  String get displayName =>
      '$surname, $firstname${(midname ?? '').isEmpty ? '' : ' $midname'}';
}

/// A single work experience entry stored as JSON inside the `experience`
/// string field.
class WorkExperienceEntry {
  WorkExperienceEntry({
    this.name = '',
    this.start,
    this.end,
    this.startPrecision = 'full',
    this.endPrecision = 'full',
  });

  factory WorkExperienceEntry.fromJson(Map<String, dynamic> json) =>
      WorkExperienceEntry(
        name: (json['name'] as String?) ?? '',
        start: json['start'] == null
            ? null
            : DateTime.tryParse(json['start'] as String),
        end: json['end'] == null
            ? null
            : DateTime.tryParse(json['end'] as String),
        startPrecision: (json['startPrecision'] as String?) ?? 'full',
        endPrecision: (json['endPrecision'] as String?) ?? 'full',
      );

  String name;
  DateTime? start;
  DateTime? end;
  String startPrecision; // 'full', 'monthYear', 'yearOnly'
  String endPrecision;   // 'full', 'monthYear', 'yearOnly'

  Map<String, dynamic> toJson() => {
        'name': name,
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
        'startPrecision': startPrecision,
        'endPrecision': endPrecision,
      };

  /// Formats a date according to its precision setting.
  String formatDate(DateTime? date, String precision, DateFormat fmt) {
    if (date == null) return '';
    switch (precision) {
      case 'yearOnly':
        return '${date.year}';
      case 'monthYear':
        return DateFormat('MMM yyyy').format(date);
      default:
        return fmt.format(date);
    }
  }
}

/// Encodes a list of work experience entries into a JSON string.
String encodeWorkExperience(List<WorkExperienceEntry> entries) =>
    jsonEncode(entries.map((e) => e.toJson()).toList());

/// Decodes a JSON string into a list of work experience entries.
/// Handles both the new JSON array format and legacy plain-text gracefully.
List<WorkExperienceEntry> decodeWorkExperience(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];
  try {
    final parsed = jsonDecode(trimmed);
    if (parsed is! List) return [];
    return parsed
        .map((e) => WorkExperienceEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // Legacy plain-text: return a single entry with the text as the name.
    return [WorkExperienceEntry(name: trimmed)];
  }
}

/// Calculates total working experience across all entries.
/// Returns (years, months) with no decimals — leftover days ≥ 15 round up.
(int years, int months) totalWorkingExperience(
    List<WorkExperienceEntry> entries) {
  var totalDays = 0;
  for (final e in entries) {
    if (e.start == null || e.end == null) continue;
    totalDays += e.end!.difference(e.start!).inDays;
  }
  if (totalDays <= 0) return (0, 0);

  final years = totalDays ~/ 365;
  final remDays = totalDays % 365;
  var months = remDays ~/ 30;
  if (remDays % 30 >= 15) months++;
  if (months >= 12) return (years + 1, 0);
  return (years, months);
}
