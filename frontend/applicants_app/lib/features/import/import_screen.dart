import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/text/name_case.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/master_data.dart';
import '../../shared/widgets/page_header.dart';
import '../auth/auth_provider.dart';
import '../master_data/widgets/form_bits.dart';
import 'import_parser.dart';

/// One target field an uploaded column can be mapped onto.
class ImportField {
  const ImportField(this.key, this.label,
      {this.required = false, this.isDate = false, this.enumOptions});
  final String key;
  final String label;
  final bool required;
  final bool isDate;
  final List<String>? enumOptions;
}

/// One applicant per row, same required fields as the manual entry form.
const _biodataFields = [
  ImportField('surname', 'Surname', required: true),
  ImportField('firstname', 'First Name', required: true),
  ImportField('midname', 'Middle Name'),
  ImportField('ext', 'Suffix (Jr., Sr., III)'),
  ImportField('dbirth', 'Date of Birth', required: true, isDate: true),
  ImportField('gender', 'Gender', required: true, enumOptions: ['Male', 'Female']),
  ImportField('civistat', 'Civil Status',
      required: true,
      enumOptions: ['Single', 'Married', 'Widowed', 'Separated']),
  ImportField('contact', 'Contact No. 1 (09XX XXX XXXX)', required: true),
  ImportField('contact2', 'Contact No. 2'),
  ImportField('houseNo', 'House No.'),
  ImportField('street', 'Street'),
  ImportField('subdivision', 'Subdivision'),
  ImportField('barangay', 'Barangay'),
  ImportField('municipality', 'Municipality', required: true),
  ImportField('district', 'District'),
  ImportField('province', 'Province', required: true),
  ImportField('education', 'Education', required: true),
  ImportField('eligibility', 'Eligibility (separate multiple with , or ;)',
      required: true),
  ImportField('experience', 'Experience'),
  ImportField('skills', 'Skills'),
  ImportField('personincharge', 'Person in Charge', required: true),
  ImportField('notes', 'Notes'),
  ImportField('lenofservice', 'Length of Service'),
  ImportField('training', 'Training'),
];

/// Optional — filled in only if at least one of these columns is mapped and
/// has a value on a given row, creating one application row for it.
const _applicationFields = [
  ImportField('position', 'Position Applied'),
  ImportField('department', 'Office / Department'),
  ImportField('appDate', 'Date Applied', isDate: true),
  ImportField('status', 'Application Status'),
];

const _synonyms = {
  'surname': ['surname', 'lastname'],
  'firstname': ['firstname', 'fname', 'givenname'],
  'midname': ['middlename', 'mname'],
  'ext': ['suffix', 'extname', 'ext'],
  'dbirth': ['dateofbirth', 'dob', 'birthdate', 'birthday'],
  'gender': ['gender', 'sex'],
  'civistat': ['civilstatus', 'civistat'],
  'contact': ['contact', 'contactno', 'contactnumber', 'mobile', 'mobileno', 'cellphone'],
  'contact2': ['contact2', 'altcontact', 'alternatecontact', 'contactno2'],
  'houseNo': ['houseno', 'housenumber'],
  'street': ['street'],
  'subdivision': ['subdivision'],
  'barangay': ['barangay', 'brgy'],
  'municipality': ['municipality', 'citytown', 'city'],
  'district': ['district'],
  'province': ['province'],
  'education': ['education', 'educationalattainment'],
  'eligibility': ['eligibility', 'eligibilities', 'civilserviceeligibility'],
  'experience': ['experience', 'workexperience'],
  'skills': ['skills'],
  'personincharge': ['personincharge', 'pic', 'encodedby'],
  'notes': ['notes', 'remarks'],
  'lenofservice': ['lengthofservice', 'yearsofservice'],
  'training': ['training', 'trainings'],
  'position': ['position', 'positionapplied', 'positionappliedfor'],
  'department': ['department', 'office'],
  'appDate': ['dateapplied', 'applicationdate', 'appdate'],
  'status': ['status', 'applicationstatus'],
};

String _normalizeHeader(String h) =>
    h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Best-guess column mapping from header text — always overridable by hand.
Map<String, String?> _guessMapping(List<String> headers) {
  final normalized = {for (final h in headers) h: _normalizeHeader(h)};
  final mapping = <String, String?>{};
  for (final field in [..._biodataFields, ..._applicationFields]) {
    final candidates = _synonyms[field.key] ?? [field.key];
    String? match;
    for (final c in candidates) {
      match = normalized.entries
          .firstWhere((e) => e.value == c, orElse: () => const MapEntry('', ''))
          .key;
      if (match.isNotEmpty) break;
    }
    mapping[field.key] = (match == null || match.isEmpty) ? null : match;
  }
  return mapping;
}

DateTime? _tryParseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  for (final pattern in ['M/d/yyyy', 'MM/dd/yyyy', 'yyyy/MM/dd', 'MMMM d, yyyy', 'MMM d, yyyy']) {
    try {
      final d = DateFormat(pattern).parseStrict(s);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      // try the next pattern
    }
  }
  return null;
}

String? _normalizeEnum(String raw, List<String> options) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  for (final o in options) {
    if (o.toLowerCase() == s.toLowerCase()) return o;
  }
  final lower = s.toLowerCase();
  if (options.contains('Male')) {
    if (lower == 'm') return 'Male';
    if (lower == 'f') return 'Female';
  }
  return s;
}

/// "Ramos" → "Ramos st." — same composition rule as the manual entry form.
String _streetPart(String street) {
  final s = street.trim();
  if (s.isEmpty) return '';
  return RegExp(r'\b(st\.?|street)$', caseSensitive: false).hasMatch(s)
      ? s
      : '$s st.';
}

/// "Poblacion" → "Brgy. Poblacion" — same rule as the manual entry form.
String _barangayPart(String barangay) {
  final s = barangay.trim();
  if (s.isEmpty) return '';
  return RegExp(r'^brgy\.?\s', caseSensitive: false).hasMatch(s)
      ? s
      : 'Brgy. $s';
}

class ImportResult {
  const ImportResult(
      {required this.rowNumber,
      required this.success,
      required this.duplicate,
      required this.errors,
      required this.label});
  factory ImportResult.fromJson(Map<String, dynamic> json, String label) =>
      ImportResult(
        rowNumber: json['rowNumber'] as int,
        success: json['success'] as bool,
        duplicate: json['duplicate'] as bool,
        errors: ((json['errors'] as List?) ?? []).cast<String>(),
        label: label,
      );

  final int rowNumber;
  final bool success;
  final bool duplicate;
  final List<String> errors;
  final String label;
}

/// 3-step batch import: upload an Excel roster, map its columns onto
/// applicant fields, then submit and review per-row results. One row =
/// one applicant, optionally with a single initial application (position /
/// office / date applied / status) — importing an applicant's full
/// interview-to-hire history isn't supported from a flat spreadsheet row;
/// add those manually afterward if needed.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  int _step = 0;
  String? _fileName;
  ParsedSheet? _sheet;
  Map<String, String?> _mapping = {};
  String? _pickError;
  bool _importing = false;
  List<ImportResult>? _results;

  bool get _canContinue => _biodataFields
      .where((f) => f.required)
      .every((f) => _mapping[f.key] != null);

  Future<void> _pickFile() async {
    setState(() => _pickError = null);
    final file = await pickImportFile();
    if (file == null) return;
    try {
      final sheet = await parseImportFile(file);
      setState(() {
        _fileName = file.name;
        _sheet = sheet;
        _mapping = _guessMapping(sheet.headers);
        _step = 1;
      });
    } on FormatException catch (e) {
      setState(() => _pickError = e.message);
    } catch (_) {
      setState(() => _pickError = 'Could not read that file.');
    }
  }

  List<Map<String, dynamic>> _buildPayload(List<String> labels) {
    final headerIndex = {
      for (var i = 0; i < _sheet!.headers.length; i++) _sheet!.headers[i]: i,
    };
    String cell(List<String> row, String field) {
      final h = _mapping[field];
      if (h == null) return '';
      final i = headerIndex[h];
      if (i == null) return '';
      return row[i].trim();
    }

    return _sheet!.rows.map((row) {
      final draft = MasterDataDraft(
        surname: cell(row, 'surname'),
        firstname: cell(row, 'firstname'),
        midname: cell(row, 'midname'),
        ext: cell(row, 'ext'),
        dbirth: _tryParseDate(cell(row, 'dbirth')),
        gender: _normalizeEnum(cell(row, 'gender'), const ['Male', 'Female']),
        civistat: _normalizeEnum(
            cell(row, 'civistat'), const ['Single', 'Married', 'Widowed', 'Separated']),
        contact: cell(row, 'contact'),
        contact2: cell(row, 'contact2'),
        houseNo: cell(row, 'houseNo'),
        street: cell(row, 'street'),
        subdivision: cell(row, 'subdivision'),
        barangay: cell(row, 'barangay'),
        municipality: cell(row, 'municipality').isEmpty ? null : cell(row, 'municipality'),
        district: cell(row, 'district'),
        province: cell(row, 'province').isEmpty ? null : cell(row, 'province'),
        education: cell(row, 'education').isEmpty ? null : cell(row, 'education'),
        experience: cell(row, 'experience'),
        skills: cell(row, 'skills'),
        personincharge:
            cell(row, 'personincharge').isEmpty ? null : cell(row, 'personincharge'),
        notes: cell(row, 'notes'),
        lenofservice: cell(row, 'lenofservice'),
        training: cell(row, 'training'),
        eligibilities: cell(row, 'eligibility')
            .split(RegExp(r'[,;]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );

      final addressParts = [
        draft.houseNo,
        _streetPart(draft.street),
        draft.subdivision,
        _barangayPart(draft.barangay),
        draft.municipality ?? '',
        draft.province ?? '',
      ].where((s) => s.trim().isNotEmpty);
      draft.address = addressParts.join(', ');

      final position = cell(row, 'position');
      final department = cell(row, 'department');
      final appDate = _tryParseDate(cell(row, 'appDate'));
      final status = cell(row, 'status');
      if (position.isNotEmpty || department.isNotEmpty || status.isNotEmpty || appDate != null) {
        draft.applications.add(ApplicationRow(
          appDate: appDate,
          position: position.isEmpty ? null : position,
          department: department.isEmpty ? null : department,
          status: status.isEmpty ? null : status,
        ));
      }

      normalizeDraftForSave(draft);
      labels.add(draft.surname.isEmpty && draft.firstname.isEmpty
          ? '(blank name)'
          : '${draft.surname}, ${draft.firstname}');
      return draft.toJson();
    }).toList();
  }

  Future<void> _submit() async {
    setState(() {
      _importing = true;
      _results = null;
    });
    final labels = <String>[];
    final payload = _buildPayload(labels);
    try {
      final api = ref.read(apiClientProvider);
      final json = await api.post('/api/masterdata/import', body: payload) as List;
      setState(() {
        _results = [
          for (var i = 0; i < json.length; i++)
            ImportResult.fromJson(json[i] as Map<String, dynamic>, labels[i]),
        ];
        _importing = false;
      });
    } catch (_) {
      setState(() => _importing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed — is the service running?')),
        );
      }
    }
  }

  void _reset() {
    setState(() {
      _step = 0;
      _fileName = null;
      _sheet = null;
      _mapping = {};
      _pickError = null;
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Import Applicants',
              parentTitle: 'Master Data',
              onParentTap: () => context.go('/master-data'),
              subtitle: 'Bring in a batch of applicants from an Excel '
                  'roster. Each row becomes one applicant record.',
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Close'),
                  onPressed: () => context.go('/master-data'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _StepHeader(step: _step),
            const SizedBox(height: AppSpacing.xl),
            if (_step == 0) _buildUploadStep(),
            if (_step == 1) _buildMappingStep(),
            if (_step == 2) _buildConfirmStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadStep() {
    return SectionCard(
      title: 'Step 1 — Upload',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _pickFile,
            borderRadius: AppRadius.mdAll,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.comboBorder, width: 1.4),
              ),
              child:               const Column(
                children: [
                  Icon(Icons.upload_file_outlined, size: 34, color: AppColors.muted),
                  SizedBox(height: 10),
                  Text('Click to choose an .xlsx file', style: AppTypography.bodyStrong),
                  SizedBox(height: 4),
                  Text('The first row must be column headers. Maximum 5,000 rows, 10 MB.',
                      style: AppTypography.helper),
                ],
              ),
            ),
          ),
          if (_pickError != null) ...[
            const SizedBox(height: 10),
            Text(_pickError!, style: AppTypography.helper.copyWith(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _buildMappingStep() {
    final sheet = _sheet!;
    final previewRows = sheet.rows.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Step 2 — Preview',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_fileName — ${sheet.rows.length} row${sheet.rows.length == 1 ? '' : 's'} detected',
                style: AppTypography.bodyStrong,
              ),
              if (sheet.rows.length > 4000)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Large file: ${sheet.rows.length} rows. Import may take a while.',
                    style: AppTypography.helper.copyWith(color: AppColors.warnInk),
                  ),
                ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowHeight: 32,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 34,
                  columns: [for (final h in sheet.headers) DataColumn(label: Text(h, style: AppTypography.sectionTitle))],
                  rows: [
                    for (final row in previewRows)
                      DataRow(cells: [
                        for (final c in row) DataCell(Text(c, style: AppTypography.helper)),
                      ]),
                  ],
                ),
              ),
              if (sheet.rows.length > previewRows.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('…and ${sheet.rows.length - previewRows.length} more row(s).',
                      style: AppTypography.helper),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Map columns',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMappingGroup('Applicant', _biodataFields),
              const SizedBox(height: AppSpacing.lg),
              _buildMappingGroup('Application (optional)', _applicationFields),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            OutlinedButton(onPressed: _reset, child: const Text('Back')),
            const Spacer(),
            ElevatedButton(
              onPressed: _canContinue ? () => setState(() => _step = 2) : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMappingGroup(String title, List<ImportField> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: AppTypography.fieldLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(
                width: 280,
                child: Labeled(
                  label: field.label,
                  required: field.required,
                  child: SearchableDropdown(
                    options: _sheet!.headers,
                    value: _mapping[field.key],
                    hint: 'Not mapped',
                    onChanged: (v) => setState(() => _mapping[field.key] = v),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    if (_results != null) return _buildResultsStep();

    return SectionCard(
      title: 'Step 3 — Confirm',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to import ${_sheet!.rows.length} applicant'
            '${_sheet!.rows.length == 1 ? '' : 's'} from $_fileName.',
            style: AppTypography.body,
          ),
          const SizedBox(height: 6),
          const Text(
            'Rows that are missing a required field, or look like a duplicate '
            'of someone already on file, will be skipped and listed after import '
            'so you can fix and re-upload just those.',
            style: AppTypography.helper,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              OutlinedButton(
                onPressed: _importing ? null : () => setState(() => _step = 1),
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: _importing
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.file_upload_outlined, size: 16),
                label: Text(_importing ? 'Importing…' : 'Start Import'),
                onPressed: _importing ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsStep() {
    final results = _results!;
    final imported = results.where((r) => r.success).length;
    final duplicates = results.where((r) => !r.success && r.duplicate).length;
    final failed = results.where((r) => !r.success && !r.duplicate).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Results',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  InfoChip('$imported imported'),
                  if (duplicates > 0) InfoChip('$duplicates possible duplicate${duplicates == 1 ? '' : 's'}', warn: true),
                  if (failed > 0) InfoChip('$failed need${failed == 1 ? 's' : ''} fixing', warn: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = results[i];
                    final icon = r.success
                        ? const Icon(Icons.check_circle, size: 16, color: AppColors.okInk)
                        : Icon(r.duplicate ? Icons.content_copy : Icons.error_outline,
                            size: 16, color: AppColors.danger);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 30,
                            child: Text('#${r.rowNumber}', style: AppTypography.caption),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(r.label, style: AppTypography.bodyStrong),
                          ),
                          Expanded(
                            flex: 3,
                            child: r.success
                                ? Text('Imported',
                                    style: AppTypography.caption.copyWith(color: AppColors.okInk))
                                : Text(r.errors.join(' '),
                                    style: AppTypography.caption.copyWith(color: AppColors.danger)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Import another file'),
              onPressed: _reset,
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => context.go('/master-data'),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final int step;

  static const _labels = ['Upload', 'Preview & Map', 'Confirm'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          _StepDot(index: i + 1, active: i == step, done: i < step),
          const SizedBox(width: 8),
          Text(_labels[i],
              style: AppTypography.helper.copyWith(
                  fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                  color: i == step ? AppColors.ink : AppColors.muted)),
          if (i < _labels.length - 1) ...[
            const SizedBox(width: 14),
            const SizedBox(width: 24, child: Divider(color: AppColors.line)),
            const SizedBox(width: 14),
          ],
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.active, required this.done});
  final int index;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active || done ? AppColors.actionBlue : AppColors.surface2,
        border: Border.all(color: active || done ? AppColors.actionBlue : AppColors.comboBorder),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : Text('$index',
              style: AppTypography.chip.copyWith(
                  color: active ? Colors.white : AppColors.muted)),
    );
  }
}
