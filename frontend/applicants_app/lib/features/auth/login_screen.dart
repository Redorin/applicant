import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../master_data/widgets/form_bits.dart';
import 'auth_provider.dart';

/// Below this width the dark left panel hides and only the form shows.
const _splitBreakpoint = 768.0;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _localError;

  @override
  void initState() {
    super.initState();
    // Rebuild on focus change so _GlowField can read hasFocus at build time
    // instead of duplicating focus-tracking state per field.
    _usernameFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _localError = 'Please enter both username and password.');
      return;
    }
    setState(() => _localError = null);

    final ok = await ref
        .read(authProvider.notifier)
        .signIn(_username.text.trim(), _password.text);
    if (ok) {
      if (mounted) context.go('/splash');
    } else {
      _password.clear();
      _passwordFocus.requestFocus();
    }
  }

  void _showForgotPasswordDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot password?'),
        content: const Text(
          'Contact your HRMDO administrator to reset your password.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final error = _localError ?? auth.error;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final form = _RightPanel(
            usernameController: _username,
            passwordController: _password,
            usernameFocus: _usernameFocus,
            passwordFocus: _passwordFocus,
            error: error,
            isBusy: auth.isBusy,
            onSubmit: _submit,
            onForgotPassword: _showForgotPasswordDialog,
          );

          if (constraints.maxWidth < _splitBreakpoint) {
            return Center(child: form);
          }
          return Row(
            children: [
              const Expanded(child: _LeftPanel()),
              SizedBox(width: 440, child: Center(child: form)),
            ],
          );
        },
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.label);
  final String icon;
  final String label;
}

const _features = [
  _Feature('📋', 'Track and manage applicant records'),
  _Feature('🔍', 'Advanced search and filtering'),
  _Feature('📊', 'Generate reports and analytics'),
  _Feature('⚡', 'Streamlined hiring workflow'),
];

class _LeftPanel extends StatelessWidget {
  const _LeftPanel();

  static const _seal = Image(
    image: AssetImage('assets/images/pgo_seal.png'),
    width: 72,
    height: 72,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.6, 1),
          colors: [AppColors.navy, AppColors.navyDeep],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -80,
            top: -80,
            child: _Circle(size: 300, color: AppColors.actionBlue.withValues(alpha: .15)),
          ),
          Positioned(
            right: -60,
            bottom: -60,
            child: _Circle(size: 200, color: AppColors.actionBlue.withValues(alpha: .10)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.actionBlue,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.actionBlue.withValues(alpha: .4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _seal,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'Applicants Info System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Human Resources Management & Development Office — '
                    'Provincial Government of Pangasinan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.sidebarTextDim,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in _features) ...[
                        _FeatureRow(feature: f),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(feature.icon, style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            feature.label,
            style: const TextStyle(color: AppColors.sidebarText, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocus,
    required this.passwordFocus,
    required this.error,
    required this.isBusy,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocus;
  final FocusNode passwordFocus;
  final String? error;
  final bool isBusy;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sign in to your account to continue',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 28),
            if (error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  border: Border.all(color: AppColors.danger.withValues(alpha: .35)),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _GlowField(
              label: 'Username',
              controller: usernameController,
              focusNode: usernameFocus,
              onSubmitted: (_) => passwordFocus.requestFocus(),
            ),
            const SizedBox(height: AppSpacing.md),
            _GlowField(
              label: 'Password',
              controller: passwordController,
              focusNode: passwordFocus,
              obscureText: true,
              onSubmitted: (_) => onSubmit(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: _ForgotPasswordLink(onTap: onForgotPassword),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SignInButton(isBusy: isBusy, onPressed: onSubmit),
            const SizedBox(height: AppSpacing.xxl),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Version 3.0.0 · HRMDO © 2026',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Forgot password?" link — a plain hover-color-swap instead of TextButton,
/// which paints a Material overlay/splash background on hover that read as
/// an unwanted shadow/box behind the text.
class _ForgotPasswordLink extends StatefulWidget {
  const _ForgotPasswordLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ForgotPasswordLink> createState() => _ForgotPasswordLinkState();
}

class _ForgotPasswordLinkState extends State<_ForgotPasswordLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          'Forgot password?',
          style: TextStyle(
            fontSize: 12,
            color: _hover ? AppColors.actionBlueHover : AppColors.actionBlue,
            decoration: _hover ? TextDecoration.underline : TextDecoration.none,
            decorationColor: AppColors.actionBlueHover,
          ),
        ),
      ),
    );
  }
}

/// Username/password field with a focused-state accent glow — the border
/// color swap comes for free from InputDecoration's own focusedBorder, but
/// the outer glow shadow needs the field's own focus state read directly
/// (Flutter has no built-in "focused shadow" on InputDecoration).
class _GlowField extends StatelessWidget {
  const _GlowField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final hasFocus = focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: .4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smAll,
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: AppColors.actionBlue.withValues(alpha: .18),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ]
                : const [],
          ),
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscureText,
              style: kValueStyle.copyWith(fontSize: 13),
              decoration: kInputDecoration.copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.smAll,
                  borderSide: const BorderSide(color: AppColors.actionBlue, width: 1.4),
                ),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-width Sign In button with a hover-darkened background, shadow, and
/// an arrow that nudges right — matches the rest of the app's hover-aware
/// button pattern (e.g. sidebar rail/drawer buttons) rather than relying on
/// ElevatedButtonTheme, since the hover-arrow-slide behavior needs its own
/// widget regardless.
class _SignInButton extends StatefulWidget {
  const _SignInButton({required this.isBusy, required this.onPressed});
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hoverActive = _hover && !widget.isBusy;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.isBusy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isBusy ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hoverActive ? AppColors.actionBlueHover : AppColors.actionBlue,
            borderRadius: BorderRadius.circular(7),
            boxShadow: hoverActive
                ? [
                    BoxShadow(
                      color: AppColors.actionBlue.withValues(alpha: .3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.isBusy ? 'Signing in…' : 'Sign In',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.only(left: hoverActive ? 10 : 8),
                child: const Icon(Icons.arrow_forward, color: Colors.white, size: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
