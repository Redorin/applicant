import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/seal_badge.dart';
import '../auth/auth_provider.dart';

/// Brief branded loading screen between login and the dashboard's first paint.
/// In testing mode it also performs the sign-in itself.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = ref.read(authProvider.notifier);
    if (kAutoLoginForTesting && !ref.read(authProvider).isSignedIn) {
      // Same office credential the login screen uses.
      final ok = await auth.signIn('hrmdo', 'ChangeMe!2026');
      if (!ok) {
        // Backend unreachable or credential changed — fall back to the
        // real login screen rather than looping.
        if (mounted) context.go('/login');
        return;
      }
    }
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SealBadge(size: 44),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Applicants Information System',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Loading your dashboard…',
              style: TextStyle(color: Color(0xFF9FADCC), fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: AppRadius.smAll,
                child: const LinearProgressIndicator(
                  minHeight: 5,
                  backgroundColor: Color(0x26FFFFFF),
                  color: AppColors.gold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
