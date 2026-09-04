import 'package:excel/excel.dart' hide Border;
import 'package:file_selector/file_selector.dart';

const maxImportRows = 5000;
const maxImportFileSize = 10 * 1024 * 1024; // 10 MB

/// A parsed spreadsheet: header row + data rows, all cells as plain text.
/// Every row is padded/truncated to `headers.length` so callers never index
/// out of range. Blank rows (all cells empty) are dropped.
class ParsedSheet {
  const ParsedSheet({required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
}

Future<XFile?> pickImportFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'Excel', extensions: ['xlsx']),
  ],
);

/// Throws [FormatException] if the file is invalid or has no usable rows.
/// Accepts only `.xlsx` files.
Future<ParsedSheet> parseImportFile(XFile file) async {
  final name = file.name;
  if (!name.toLowerCase().endsWith('.xlsx')) {
    throw const FormatException('Only .xlsx files are supported. Please export your data as an Excel file.');
  }

  final bytes = await file.readAsBytes();

  if (bytes.lengthInBytes > maxImportFileSize) {
    throw const FormatException('File is too large. The maximum size is 10 MB.');
  }

  if (bytes.isEmpty) {
    throw const FormatException('The file is empty.');
  }

  final table = _parseXlsx(bytes);

  if (table.isEmpty) {
    throw const FormatException('The file has no rows.');
  }

  final headers = table.first.map((c) => c.trim()).toList();
  if (headers.every((h) => h.isEmpty)) {
    throw const FormatException('Could not find a header row.');
  }

  final rows = table
      .skip(1)
      .where((r) => r.any((c) => c.trim().isNotEmpty))
      .map((r) {
        final padded = List<String>.filled(headers.length, '');
        for (var i = 0; i < headers.length && i < r.length; i++) {
          padded[i] = r[i];
        }
        return padded;
      })
      .toList();

  if (rows.isEmpty) {
    throw const FormatException('The file has headers but no data rows.');
  }

  if (rows.length > maxImportRows) {
    throw const FormatException(
      'The file has more than 5,000 rows. Please split it into smaller batches.',
    );
  }

  return ParsedSheet(headers: headers, rows: rows);
}

List<List<String>> _parseXlsx(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheetName = excel.getDefaultSheet();
  if (sheetName == null) return const [];
  final sheet = excel[sheetName];
  return sheet.rows
      .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
      .toList();
}
