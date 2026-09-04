import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:applicants_app/features/shell/app_shell.dart';
import 'package:applicants_app/features/shell/sidebar_nav_items.dart';
import 'package:applicants_app/features/shell/sidebar_rail.dart';
import 'package:applicants_app/features/shell/sidebar_state.dart';

Widget _harness() => const ProviderScope(
      child: MaterialApp(
        home: AppShell(currentPath: '/dashboard', child: SizedBox()),
      ),
    );

// A minimal real router (rather than a plain MaterialApp) so `context.go`
// inside handleNavTap doesn't throw — needed to exercise an actual drawer
// row tap end-to-end instead of just the provider in isolation.
Widget _harnessWithRouter() {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      for (final item in sidebarNavItems)
        GoRoute(
          path: item.path,
          builder: (context, state) =>
              AppShell(currentPath: state.uri.path, child: const SizedBox()),
        ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

// Matches the real window this sidebar runs in; the default 800x600 test
// viewport is too short for its content (see sidebar_nav_test.dart). Width
// is deliberately above the 900px narrow-sidebar breakpoint so these tests
// exercise the normal (rail always visible, 74px closed hover width) case —
// see _useNarrowViewport below for the <900px behavior.
void _useRealisticViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1050);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Below the 900px breakpoint: the rail hides and the closed-state hover
// strip shrinks to 10px (see _SidebarHoverZone in app_shell.dart).
void _useNarrowViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1050);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('hovering the rail opens the drawer', (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);
    expect(container.read(sidebarDrawerProvider), isFalse);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(37, 100)); // inside the 74px rail
    await tester.pump();

    expect(container.read(sidebarDrawerProvider), isTrue);
    await gesture.removePointer();
  });

  testWidgets('moving from the rail into the opened drawer keeps it open',
      (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(37, 100));
    await tester.pump();
    expect(container.read(sidebarDrawerProvider), isTrue);

    // Move further right, still inside the 240px drawer footprint.
    await gesture.moveTo(const Offset(150, 300));
    await tester.pump();
    expect(container.read(sidebarDrawerProvider), isTrue,
        reason: 'drawer must stay open while hovering within its own footprint');

    await gesture.removePointer();
  });

  testWidgets('leaving the drawer footprint closes it immediately',
      (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(37, 100));
    await tester.pump();
    expect(container.read(sidebarDrawerProvider), isTrue);

    // Move past the drawer's right edge (240px), into the content area.
    await gesture.moveTo(const Offset(400, 300));
    await tester.pump();

    expect(container.read(sidebarDrawerProvider), isFalse,
        reason: 'provider should flip closed with no delay once the cursor '
            'leaves the 0-240 hover band');

    await gesture.removePointer();
  });

  testWidgets('no hamburger/menu icon remains anywhere in the sidebar',
      (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);
    container.read(sidebarDrawerProvider.notifier).open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // let the slide-in finish

    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets(
      'hovering page content past the rail (drawer closed) does not open it',
      (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // x=100 is past the 74px rail but within the old (buggy) fixed 240px
    // catcher — regression test for the hover zone being sized to the
    // rail's actual footprint while closed.
    await gesture.addPointer(location: const Offset(100, 300));
    await tester.pump();

    expect(container.read(sidebarDrawerProvider), isFalse,
        reason: 'the rail is only 74px wide while closed; content beyond '
            'that must not trigger the drawer');

    await gesture.removePointer();
  });

  testWidgets('clicking a drawer nav row navigates without closing the drawer',
      (tester) async {
    _useRealisticViewport(tester);
    await tester.pumpWidget(_harnessWithRouter());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);

    // Open directly via the provider rather than a mouse hover gesture: a
    // lingering mouse pointer would still be geometrically inside the rail's
    // 0-74 band after navigation, and since GoRoute page transitions replace
    // the whole widget subtree (a brand new _SidebarHoverZone render object),
    // Flutter's mouse tracker would synthesize a fresh onEnter for that new
    // object purely from the pointer's stationary position — reopening the
    // drawer regardless of whether the close-on-navigate bug is present, and
    // masking the very regression this test exists to catch.
    container.read(sidebarDrawerProvider.notifier).open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // let the slide-in finish before tapping

    await tester.tap(find.text('List of Applicants'));
    await tester.pumpAndSettle();

    expect(container.read(sidebarDrawerProvider), isTrue,
        reason: 'navigating via a drawer row must not force-close the '
            'drawer — only hover-exit, backdrop click, or Escape should');
  });

  testWidgets('below 900px, the rail is hidden and a slim hover strip opens the drawer',
      (tester) async {
    _useNarrowViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    // The full 74px rail is gone at this width.
    expect(find.byType(SidebarRail), findsNothing);

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);
    expect(container.read(sidebarDrawerProvider), isFalse);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // x=5 is inside the narrow 10px strip but would also be inside the old
    // 74px rail — the point of this test is the strip below.
    await gesture.addPointer(location: const Offset(5, 100));
    await tester.pump();
    expect(container.read(sidebarDrawerProvider), isTrue,
        reason: 'the narrow hover strip should still open the drawer');

    await gesture.removePointer();
  });

  testWidgets('below 900px, content just past the narrow strip does not open the drawer',
      (tester) async {
    _useNarrowViewport(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    final element = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(element);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // x=50 is well past the narrow 10px strip but was inside the old 74px
    // rail — confirms the closed-state hover width actually shrank.
    await gesture.addPointer(location: const Offset(50, 100));
    await tester.pump();
    expect(container.read(sidebarDrawerProvider), isFalse,
        reason: 'closed-state hover width should be ~10px below the '
            'breakpoint, not the old 74px rail width');

    await gesture.removePointer();
  });
}
