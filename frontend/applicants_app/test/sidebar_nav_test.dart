import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:applicants_app/features/data_health/data_health_screen.dart';
import 'package:applicants_app/features/shell/sidebar_nav_items.dart';
import 'package:applicants_app/features/shell/sidebar_rail.dart';
import 'package:applicants_app/core/theme/app_colors.dart';

const _sidebarBody = MaterialApp(
  home: Scaffold(
    body: Row(
      children: [
        SidebarRail(currentPath: '/dashboard'),
        Expanded(child: SizedBox()),
      ],
    ),
  ),
);

Widget _harness() => const ProviderScope(child: _sidebarBody);

// The default flutter_test viewport (800x600) is shorter than any real
// window this sidebar runs in and isn't tall enough for its content —
// without this, tests intermittently hit an unrelated vertical overflow
// that has nothing to do with what's actually being tested.
void _useRealisticViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1050);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders once with no exceptions', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('all nav icons are present', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    for (final item in sidebarNavItems) {
      expect(find.byIcon(item.icon), findsWidgets,
          reason: '${item.label} icon should be in the rail');
    }
    expect(find.byIcon(Icons.settings), findsOneWidget,
        reason: 'Settings/Preferences icon should be in the rail');
  });

  testWidgets('badge dot appears for Data Health when count > 0',
      (tester) async {
    _useRealisticViewport(tester);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthSummaryProvider.overrideWith(
          (ref) async => [const HealthCategory('missing-fields', 'Missing Fields', '', 1770)],
        ),
      ],
      child: _sidebarBody,
    ));
    await tester.pump();
    await tester.pump(); // let the FutureProvider resolve

    // The badge is a small 7px dot, not a text label — find it via the
    // Positioned widget inside the Data Health icon's _RailIconButton.
    final dataHealthIcon = find.byIcon(Icons.health_and_safety);
    expect(dataHealthIcon, findsOneWidget);

    // The dot is a Container with a circle shape inside a Stack near the icon.
    // Verify the icon's ancestor Stack contains a Positioned badge.
    final stack = tester.widget<Stack>(
      find.ancestor(
        of: find.byIcon(Icons.health_and_safety),
        matching: find.byType(Stack),
      ).first,
    );
    expect(
      stack.children.any((child) =>
          child is Positioned &&
          child.child is Container &&
          (child.child as Container).decoration is BoxDecoration &&
          ((child.child as Container).decoration as BoxDecoration).shape ==
              BoxShape.circle),
      isTrue,
      reason: 'Data Health icon should have a red dot badge',
    );
  });

  testWidgets('badge dot does not appear when count is 0', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final dataHealthIcon = find.byIcon(Icons.health_and_safety);
    expect(dataHealthIcon, findsOneWidget);

    final stack = tester.widget<Stack>(
      find.ancestor(
        of: find.byIcon(Icons.health_and_safety),
        matching: find.byType(Stack),
      ).first,
    );
    expect(
      stack.children.every((child) =>
          child is! Positioned ||
          child.child is! Container ||
          (child.child as Container).decoration is! BoxDecoration ||
          ((child.child as Container).decoration as BoxDecoration).shape !=
              BoxShape.circle),
      isTrue,
      reason: 'No badge dot should exist when health count is 0',
    );
  });

  testWidgets('rail width is fixed at 74px', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    tester.widget<SidebarRail>(find.byType(SidebarRail));
    expect(SidebarRail.width, 74.0);
  });

  testWidgets('active indicator shows for current path', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SidebarRail(currentPath: '/master-data'),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    // The Master Data icon should have a gold active indicator bar.
    final masterDataIcon = find.byIcon(Icons.person);
    expect(masterDataIcon, findsOneWidget);

    // The active indicator is a 3px-wide Container with gold color
    // positioned at left:0, top:8, bottom:8 inside the icon's Stack.
    // Look for any Container widget with the gold color in the tree.
    final goldContainers = find.byWidgetPredicate((widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color == AppColors.gold);
    expect(goldContainers, findsWidgets,
        reason: 'Active nav item should have a gold indicator bar');
  });
}
