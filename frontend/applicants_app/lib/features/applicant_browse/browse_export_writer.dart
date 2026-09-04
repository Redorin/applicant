import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import 'applicant_browse_provider.dart';

// Letterhead colors, matching the PDF reports' masthead (see
// ReportStyle.cs — Navy/Surface2/Line) so the Excel export reads as the
// same document family as the printed reports.
final _gridLine = ExcelColor.fromHexString('FFD0D5DD');
final _zebraStripe = ExcelColor.fromHexString('FFF8FAFC');
final _headerBg = ExcelColor.fromHexString('FF1E2F4D');

/// Writes the "Republic of the Philippines / PROVINCE OF PANGASINAN /
/// HUMAN RESOURCE MANAGEMENT & DEVELOPMENT OFFICE / Lingayen, Pangasinan /
/// `<report title>`" masthead used by every PDF report (ReportStyle.Letterhead),
/// merged across columns 1..lastCol — column 0 is left clear so the seal
/// image (added later by [_embedSealImage]) has its own space on the left,
/// matching the printed letterhead layout. Returns the row index the actual
/// data table should start at.
int _writeLetterhead(Sheet sheet, int columnCount, String reportTitle) {
  final lastCol = columnCount - 1;
  final textCol = columnCount > 1 ? 1 : 0;

  void line(
    int row,
    String text, {
    required double fontSize,
    bool bold = false,
    bool banner = false,
    String? fontColor,
  }) {
    final start = CellIndex.indexByColumnRow(
      columnIndex: textCol,
      rowIndex: row,
    );
    if (lastCol > textCol) {
      sheet.merge(
        start,
        CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row),
      );
    }
    sheet.updateCell(
      start,
      TextCellValue(text),
      cellStyle: CellStyle(
        bold: bold,
        fontSize: fontSize.round(),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        fontColorHex: fontColor != null
            ? ExcelColor.fromHexString(fontColor)
            : banner
                ? ExcelColor.white
                : ExcelColor.black,
        backgroundColorHex: banner ? _headerBg : ExcelColor.none,
      ),
    );
  }

  // Row heights for the letterhead section
  sheet.setRowHeight(0, 18);
  sheet.setRowHeight(1, 24);
  sheet.setRowHeight(2, 20);
  sheet.setRowHeight(3, 18);
  sheet.setRowHeight(4, 26);

  line(0, 'Republic of the Philippines', fontSize: 10);
  line(1, 'PROVINCE OF PANGASINAN', fontSize: 16, bold: true);
  line(
    2,
    'HUMAN RESOURCE MANAGEMENT & DEVELOPMENT OFFICE',
    fontSize: 12,
    bold: true,
  );
  line(3, 'Lingayen, Pangasinan', fontSize: 10);
  line(4, reportTitle.toUpperCase(), fontSize: 13, bold: true, banner: true);

  // Row 5 is left blank as a spacer before the data table.
  return 6;
}

/// Embeds the provincial seal into the letterhead's reserved column-0 area.
///
/// The `excel` package (any version, per its changelog) has no picture API
/// at all — cells only. But `Excel.createExcel()`'s blank template already
/// ships an empty `xl/drawings/drawing1.xml` wired to the sheet via
/// `<drawing r:id="rId1"/>` and a matching worksheet rels entry (evidently
/// meant for exactly this). So instead of hand-rolling a whole new drawing
/// part, this fills in that existing empty drawing with a single anchored
/// picture, adds the image bytes as `xl/media/image1.png`, and registers the
/// `png` content type (the template doesn't declare one, since it ships with
/// no images).
Future<Uint8List> _embedSealImage(List<int> xlsxBytes) async {
  final sealAsset = await rootBundle.load('assets/images/pgo_seal.png');
  final sealBytes = sealAsset.buffer.asUint8List(
    sealAsset.offsetInBytes,
    sealAsset.lengthInBytes,
  );

  final archive = ZipDecoder().decodeBytes(xlsxBytes);

  // ~100x100px square (EMU = px * 9525), anchored just inside the top-left
  // corner of the reserved column — big enough to read, small enough to sit
  // fully inside the six letterhead rows.
  const emuSize = 100 * 9525;
  const drawingXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr '
      'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<xdr:oneCellAnchor>'
      '<xdr:from><xdr:col>0</xdr:col><xdr:colOff>19050</xdr:colOff>'
      '<xdr:row>0</xdr:row><xdr:rowOff>19050</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="$emuSize" cy="$emuSize"/>'
      '<xdr:pic>'
      '<xdr:nvPicPr><xdr:cNvPr id="2" name="Provincial Seal"/>'
      '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
      '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$emuSize" cy="$emuSize"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
      '</xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>';

  const drawingRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="../media/image1.png"/></Relationships>';

  archive.addFile(ArchiveFile.string('xl/drawings/drawing1.xml', drawingXml));
  archive.addFile(
    ArchiveFile.string('xl/drawings/_rels/drawing1.xml.rels', drawingRels),
  );
  archive.addFile(
    ArchiveFile('xl/media/image1.png', sealBytes.length, sealBytes),
  );

  final contentTypesFile = archive.findFile('[Content_Types].xml')!;
  final contentTypesXml = utf8.decode(contentTypesFile.content as List<int>);
  if (!contentTypesXml.contains('Extension="png"')) {
    archive.addFile(
      ArchiveFile.string(
        '[Content_Types].xml',
        contentTypesXml.replaceFirst(
          '<Default ContentType="application/xml" Extension="xml"/>',
          '<Default ContentType="application/xml" Extension="xml"/>'
              '<Default ContentType="image/png" Extension="png"/>',
        ),
      ),
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Column set for one exported row — shared by the Excel and CSV writers so
/// they can never drift from each other.
List<String> _headersFor(bool hiredOnly) => hiredOnly
    ? const [
        'Applicant',
        'Municipality',
        'Date Hired',
        'Final Position',
        'Final Department',
      ]
    : const [
        'Applicant',
        'Municipality',
        'Position Applied',
        'Office',
        'Date Applied',
        'Status',
      ];

List<String> _valuesFor(BrowseRow row, bool hiredOnly, DateFormat dateFmt) {
  String d(DateTime? v) => v == null ? '' : dateFmt.format(v);
  return hiredOnly
      ? [
          row.applicant,
          row.municipality ?? '',
          d(row.hiredDate),
          row.finalPosition ?? '',
          row.finalDepartment ?? '',
        ]
      : [
          row.applicant,
          row.municipality ?? '',
          row.position ?? '',
          row.department ?? '',
          d(row.appDate),
          row.status ?? '',
        ];
}

/// Writes [rows] to a real .xlsx file via a save-location prompt. Returns
/// `false` if the user cancelled the prompt (nothing was written).
Future<bool> exportRowsToExcel(
  List<BrowseRow> rows, {
  required bool hiredOnly,
  required bool includeHeaderRow,
  required bool includeTimestamps,
  required String suggestedFileName,
}) async {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  final dateFmt = DateFormat('MMM dd, yyyy');
  final headers = _headersFor(hiredOnly);
  final columnCount = headers.length;

  var r = _writeLetterhead(
    sheet,
    columnCount,
    hiredOnly ? 'Hired Applicants' : 'List of Applicants',
  );

  Border gridBorder() =>
      Border(borderStyle: BorderStyle.Thin, borderColorHex: _gridLine);

  void writeRow(int rowIndex, List<String> values, {bool header = false}) {
    for (var c = 0; c < values.length; c++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex),
        TextCellValue(values[c]),
        cellStyle: CellStyle(
          bold: header,
          fontSize: header ? 10 : 10,
          horizontalAlign: header
              ? HorizontalAlign.Center
              : c == 0
                  ? HorizontalAlign.Left
                  : HorizontalAlign.Left,
          verticalAlign: VerticalAlign.Center,
          fontColorHex: header ? ExcelColor.white : ExcelColor.black,
          backgroundColorHex: header
              ? _headerBg
              : rowIndex.isOdd
                  ? _zebraStripe
                  : ExcelColor.none,
          leftBorder: gridBorder(),
          rightBorder: gridBorder(),
          topBorder: gridBorder(),
          bottomBorder: gridBorder(),
        ),
      );
    }
  }

  if (includeHeaderRow) {
    sheet.setRowHeight(r, 22);
    writeRow(r, headers, header: true);
    r++;
  }

  for (final row in rows) {
    sheet.setRowHeight(r, 18);
    writeRow(r, _valuesFor(row, hiredOnly, dateFmt));
    r++;
  }

  if (includeTimestamps) {
    r++; // blank spacer row
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      TextCellValue('Exported:'),
      cellStyle: CellStyle(
        bold: true,
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('FF6B7280'),
      ),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r),
      TextCellValue(DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())),
      cellStyle: CellStyle(
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('FF6B7280'),
      ),
    );
  }

  // Auto-fit column widths based on header + max content length
  for (var i = 0; i < columnCount; i++) {
    var maxLen = headers[i].length;
    for (final row in rows) {
      final vals = _valuesFor(row, hiredOnly, dateFmt);
      if (i < vals.length) {
        maxLen = max(maxLen, vals[i].length);
      }
    }
    sheet.setColumnWidth(i, (maxLen + 4).toDouble());
  }

  final rawBytes = excel.encode();
  if (rawBytes == null) return false;
  final bytes = await _embedSealImage(rawBytes);

  final location = await getSaveLocation(
    suggestedName: suggestedFileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel', extensions: ['xlsx']),
    ],
  );
  if (location == null) return false;
  await File(location.path).writeAsBytes(bytes);
  return true;
}

/// Writes [rows] to a real .csv file via a save-location prompt. Returns
/// `false` if the user cancelled the prompt (nothing was written).
Future<bool> exportRowsToCsv(
  List<BrowseRow> rows, {
  required bool hiredOnly,
  required bool includeHeaderRow,
  required bool includeTimestamps,
  required String suggestedFileName,
}) async {
  final dateFmt = DateFormat('MMM dd, yyyy');
  final table = <List<String>>[
    if (includeHeaderRow) _headersFor(hiredOnly),
    for (final row in rows) _valuesFor(row, hiredOnly, dateFmt),
    if (includeTimestamps)
      ['Exported', DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())],
  ];
  final csv = Csv().encode(table);

  final location = await getSaveLocation(
    suggestedName: suggestedFileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV', extensions: ['csv']),
    ],
  );
  if (location == null) return false;
  await File(location.path).writeAsString(csv);
  return true;
}
