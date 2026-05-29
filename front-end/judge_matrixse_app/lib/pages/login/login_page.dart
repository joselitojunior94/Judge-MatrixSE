import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/gradient_background.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();
  bool _busy = false;
  String? _err;
  bool _showRegister = false;

  @override
  void dispose() {
    _motion.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _err = 'Enter username and password.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    try {
      if (_showRegister) {
        await AuthService.instance.register(username, password);
      } else {
        await AuthService.instance.login(username, password);
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: AnimatedBuilder(
          animation: _motion,
          builder:
              (context, _) => CustomPaint(
                painter: _LoginMotionPainter(_motion.value),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760;
                        final brand = _LogoStage(
                          compact: compact,
                          progress: _motion.value,
                        );
                        final form = _LoginForm(
                          username: _username,
                          password: _password,
                          busy: _busy,
                          error: _err,
                          showRegister: _showRegister,
                          onModeChanged:
                              (value) => setState(() {
                                _showRegister = value;
                                _err = null;
                              }),
                          onSubmit: _submit,
                        );

                        if (compact) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                brand,
                                const SizedBox(height: 18),
                                form,
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(child: brand),
                              const SizedBox(width: 18),
                              Flexible(child: form),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}

class _LogoStage extends StatelessWidget {
  const _LogoStage({required this.compact, required this.progress});

  final bool compact;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 220.0 : 360.0;
    return SizedBox(
      height: compact ? 240 : 430,
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Transform.rotate(
                  angle:
                      (progress * math.pi * 2) * (i.isEven ? 1 : -1) +
                      i * math.pi / 3,
                  child: Container(
                    width: size - i * 58,
                    height: size - i * 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: [
                          AppTheme.cyan,
                          AppTheme.mint,
                          AppTheme.rose,
                        ][i].withValues(alpha: .22),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 8 + i * 2,
                        height: 8 + i * 2,
                        decoration: BoxDecoration(
                          color:
                              [AppTheme.cyan, AppTheme.mint, AppTheme.rose][i],
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: [
                                AppTheme.cyan,
                                AppTheme.mint,
                                AppTheme.rose,
                              ][i].withValues(alpha: .45),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                width: size * .72,
                height: size * .72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .045),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: .15),
                      blurRadius: 60,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 1 + math.sin(progress * math.pi * 2) * .025,
                child: Image.asset(
                  'assets/images/logo.png',
                  width: size * .62,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.username,
    required this.password,
    required this.busy,
    required this.error,
    required this.showRegister,
    required this.onModeChanged,
    required this.onSubmit,
  });

  final TextEditingController username;
  final TextEditingController password;
  final bool busy;
  final String? error;
  final bool showRegister;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassCard(
      interactive: false,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_without_background.png',
              height: 168,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Log in')),
                ButtonSegment(value: true, label: Text('Register')),
              ],
              selected: {showRegister},
              onSelectionChanged: (selection) => onModeChanged(selection.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: username,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onSubmit,
                icon:
                    busy
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Icon(
                          showRegister
                              ? Icons.person_add_outlined
                              : Icons.login,
                        ),
                label: Text(showRegister ? 'Create account' : 'Log in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginMotionPainter extends CustomPainter {
  const _LoginMotionPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    for (var i = 0; i < 18; i++) {
      final t = (progress + i / 18) % 1;
      final x = size.width * ((i * 0.173 + t * .16) % 1);
      final y =
          size.height * ((i * 0.317 + math.sin(t * math.pi * 2) * .04) % 1);
      paint.color = [AppTheme.cyan, AppTheme.indigo, AppTheme.mint][i %
          3].withValues(alpha: .06 + .10 * (1 - t));
      canvas.drawCircle(Offset(x, y), 18 + (i % 5) * 11, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoginMotionPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
