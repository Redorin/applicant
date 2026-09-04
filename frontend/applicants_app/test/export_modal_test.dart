import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:applicants_app/features/applicant_browse/export_modal.dart';

// Matches a real desktop window; the default 800x600 test viewport is short
// enough that the modal's lower controls (Include timestamps, Export) sit
// past the fold, which is realistic for a genuinely short window (the modal
// correctly scrolls there) but makes literal-pixel test taps on those
// controls unreliable without scrolling logic the test doesn't need.
void _useRealisticViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<Future<ExportChoice?>> _openModal(WidgetTester tester, {required bool hasSelection}) async {
  late final Future<ExportChoice?> result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            result = showExportModal(context, hasSelection: hasSelection);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('defaults to PDF format and "Selected rows" scope when a selection exists',
      (tester) async {
    _useRealisticViewport(tester);
    await _openModal(tester, hasSelection: true);

    expect(find.text('Export applicants'), findsOneWidget);
    final selectedTile = tester.widget<RadioListTile<ExportScope>>(
      find.byWidgetPredicate(
        (w) => w is RadioListTile<ExportScope> && w.value == ExportScope.selected,
      ),
    );
    expect(selectedTile.enabled, isTrue);
  });

  testWidgets('"Selected rows" is disabled when there is no selection', (tester) async {
    _useRealisticViewport(tester);
    await _openModal(tester, hasSelection: false);

    final selectedTile = tester.widget<RadioListTile<ExportScope>>(
      find.byWidgetPredicate(
        (w) => w is RadioListTile<ExportScope> && w.value == ExportScope.selected,
      ),
    );
    expect(selectedTile.enabled, isFalse);
  });

  testWidgets('choosing Excel and Export returns the expected ExportChoice', (tester) async {
    _useRealisticViewport(tester);
    final result = await _openModal(tester, hasSelection: false);

    await tester.tap(find.text('Excel'));
    await tester.pump();
    await tester.tap(find.text('Filtered results'));
    await tester.pump();
    await tester.tap(find.text('Include timestamps'));
    await tester.pump();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    final choice = await result;
    expect(choice, isNotNull);
    expect(choice!.format, ExportFormat.excel);
    expect(choice.scope, ExportScope.filtered);
    expect(choice.includeHeaderRow, isTrue); // default, untouched
    expect(choice.includeTimestamps, isTrue); // toggled on above
  });

  testWidgets('Cancel returns null', (tester) async {
    _useRealisticViewport(tester);
    final result = await _openModal(tester, hasSelection: false);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('Escape closes the modal with null', (tester) async {
    _useRealisticViewport(tester);
    final result = await _openModal(tester, hasSelection: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('does not overflow at a short/small window size', (tester) async {
    // Deliberately the small default viewport (no _useRealisticViewport) —
    // this is the regression test for the overflow bug fixed by wrapping
    // the modal's body in a scrollable Flexible region.
    await _openModal(tester, hasSelection: false);
    expect(tester.takeException(), isNull);
  });
}
