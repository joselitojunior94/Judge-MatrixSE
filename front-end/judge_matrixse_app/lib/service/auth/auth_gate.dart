import 'package:flutter/material.dart';

import '../../components/shell.dart';
import '../../pages/login/login_page.dart';
import 'auth_service.dart';

/// Root widget that listens to [AuthService] and swaps between
/// [LoginPage] and [Shell] as the auth state changes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showingSessionExpiredDialog = false;

  @override
  void initState() {
    super.initState();
    // Kick off token loading; the listener below will rebuild when done.
    if (!AuthService.instance.initialised) {
      AuthService.instance.init().then((_) {
        if (mounted) setState(() {});
      });
    }
    AuthService.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeShowSessionExpiredDialog();
  }

  void _maybeShowSessionExpiredDialog() {
    final auth = AuthService.instance;
    if (!auth.sessionExpired || _showingSessionExpiredDialog || !mounted) {
      return;
    }
    _showingSessionExpiredDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !AuthService.instance.sessionExpired) {
        _showingSessionExpiredDialog = false;
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Session expired'),
              content: const Text(
                'Your session has expired. Please sign in again to continue.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      await AuthService.instance.acknowledgeSessionExpired();
      _showingSessionExpiredDialog = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    if (!auth.initialised) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.sessionExpired) {
      _maybeShowSessionExpiredDialog();
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return auth.isLoggedIn ? const Shell() : const LoginPage();
  }
}
