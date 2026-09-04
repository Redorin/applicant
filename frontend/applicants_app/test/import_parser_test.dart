import 'dart:typed_data';

import 'package:applicants_app/features/import/import_parser.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

XFile _fileFrom(String path, Uint8List bytes) =>
    XFile.fromData(bytes, path: path);

void main() {
  group('parseImportFile — rejects non-XLSX', () {
    test('CSV files are rejected', () async {
      final file = _fileFrom(
          'roster.csv', Uint8List.fromList([0x41, 0x42, 0x43])); // "ABC"
      expect(() => parseImportFile(file), throwsFormatException);
    });

    test('throws on an empty file', () async {
      final file = _fileFrom('roster.xlsx', Uint8List(0));
      expect(() => parseImportFile(file), throwsFormatException);
    });
  });

  group('parseImportFile — XLSX', () {
    test('reads a workbook built with the excel package', () async {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      sheet.appendRow([TextCellValue('Surname'), TextCellValue('Date of Birth')]);
      sheet.appendRow([
        TextCellValue('Zzprobe'),
        const DateCellValue(year: 1990, month: 5, day: 14),
      ]);
      final bytes = excel.save()!;

      final parsed =
          await parseImportFile(_fileFrom('roster.xlsx', Uint8List.fromList(bytes)));

      expect(parsed.headers, ['Surname', 'Date of Birth']);
      expect(parsed.rows.length, 1);
      expect(parsed.rows.first[0], 'Zzprobe');
      // Date cells round-trip as an ISO-ish string that DateTime.parse can read.
      expect(DateTime.parse(parsed.rows.first[1]).year, 1990);
    });
  });
}
