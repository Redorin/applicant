import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class ApplicantsApp extends StatelessWidget {
  const ApplicantsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Applicants Information System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
      // Respect the user's real OS/accessibility text-scale setting instead
      // of overriding it, but clamp so extreme OS settings can't break the
      // fixed-density desktop layout.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped =
            mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child!,
        );
      },
    );
  }
}
