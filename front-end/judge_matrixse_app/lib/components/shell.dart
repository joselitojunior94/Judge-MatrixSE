import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/feedback_form_dialog.dart';
import '../components/notifications_dialog.dart';
import '../components/tutorial_anchor.dart';
import '../components/tutorial_overlay.dart';
import '../components/user_avatar.dart';
import '../pages/evaluations/evaluations_page.dart';
import '../pages/evaluations/public_evaluations_page.dart';
import '../pages/home/home_page.dart';
import '../pages/people/people_page.dart';
import '../pages/profile/profile_page.dart';
import '../pages/rankings/rankings_page.dart';
import '../pages/tutorial/tutorial_page.dart';
import '../pages/wizard/wizard_page.dart';
import '../service/auth/auth_service.dart';
import '../service/tutorial/tutorial_controller.dart';
import '../service/tutorial/tutorial_steps.dart';
import '../theme/app_theme.dart';
import 'nav_rail.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _feedbackDelay = Duration(minutes: 10);
  static const _mobileDestinations = <_ShellDestination>[
    _ShellDestination('Home', Icons.home_outlined, 0),
    _ShellDestination('Datasets', Icons.upload_file_outlined, 1),
    _ShellDestination('Evaluations', Icons.fact_check_outlined, 2),
    _ShellDestination('Public', Icons.travel_explore_outlined, 3),
    _ShellDestination('People', Icons.groups_2_outlined, 4),
    _ShellDestination('Profile', Icons.person_outline, 5),
    _ShellDestination('Rankings', Icons.emoji_events_outlined, 6),
  ];

  int _idx = 0;
  Timer? _feedbackTimer;
  Timer? _notificationTimer;
  bool _feedbackDialogOpen = false;
  int _unreadNotifications = 0;

  void _go(int i) {
    setState(() => _idx = i);
    if (i == 7) {
      TutorialController.instance.start(restart: true);
    }
  }

  void _goFromTutorial(int i) {
    if (_idx == i) return;
    setState(() => _idx = i);
  }

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    TutorialController.instance.addListener(_onTutorialChanged);
    _initTutorial();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    TutorialController.instance.removeListener(_onTutorialChanged);
    _feedbackTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _onAuthChanged() {
    // If the user was logged out (e.g. refresh failed), AuthGate rebuilds.
    _initTutorial();
    _scheduleFeedbackPrompt();
    if (mounted) setState(() {});
  }

  void _onTutorialChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initTutorial() async {
    final auth = AuthService.instance;
    if (!auth.isLoggedIn || auth.currentUser == null) return;
    await TutorialController.instance.initForUser(auth.username);
    _scheduleFeedbackPrompt();
    _startNotificationPolling();
  }

  void _startNotificationPolling() {
    _notificationTimer?.cancel();
    _loadNotificationCount();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadNotificationCount(),
    );
  }

  Future<void> _loadNotificationCount() async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      final data = await AuthService.instance.api.notifications();
      if (!mounted) return;
      setState(() => _unreadNotifications = data['unread'] as int? ?? 0);
    } catch (_) {
      // Notification count should never block the shell.
    }
  }

  Future<void> _scheduleFeedbackPrompt() async {
    _feedbackTimer?.cancel();
    final auth = AuthService.instance;
    if (!auth.isLoggedIn || auth.currentUser == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _feedbackPreferenceKey(auth.username);
    if (prefs.getBool(key) == true) return;

    _feedbackTimer = Timer(_feedbackDelay, () {
      if (!mounted || _feedbackDialogOpen || !AuthService.instance.isLoggedIn) {
        return;
      }
      _showFeedbackPrompt();
    });
  }

  String _feedbackPreferenceKey(String username) =>
      'judgematrixse_feedback_form_done_$username';

  Future<void> _rememberFeedbackDecision() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _feedbackPreferenceKey(AuthService.instance.username),
      true,
    );
  }

  Future<void> _showFeedbackPrompt() async {
    _feedbackDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => FeedbackFormDialog(
            onSkip: () async {
              await _rememberFeedbackDecision();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            onDone: () async {
              await _rememberFeedbackDecision();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
          ),
    );
    _feedbackDialogOpen = false;
  }

  Future<void> _logout(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder:
          (_) => AlertDialog(
            title: const Text('Log out?'),
            content: const Text('Your session will be ended.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Log out'),
              ),
            ],
          ),
    );
    if (ok == true) await AuthService.instance.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.width < 720;
    final pages = [
      HomePage(onGetStarted: () => _go(1), onSeeEvals: () => _go(2)),
      const WizardPage(),
      const EvaluationsPage(),
      const PublicEvaluationsPage(),
      const PeoplePage(),
      const ProfilePage(),
      const RankingsPage(),
      const TutorialPage(),
    ];

    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder:
          (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.012, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
      child: KeyedSubtree(key: ValueKey(_idx), child: pages[_idx]),
    );

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppTheme.background,
          drawer: isPhone ? _buildMobileDrawer(auth) : null,
          appBar: AppBar(
            elevation: 0,
            toolbarHeight: isPhone ? 60 : 68,
            centerTitle: false,
            leading:
                isPhone
                    ? Builder(
                      builder:
                          (ctx) => IconButton(
                            tooltip: 'Menu',
                            icon: const Icon(Icons.menu_rounded),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                    )
                    : null,
            flexibleSpace: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: .72),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
              ),
            ),
            title: const TutorialAnchor(
              target: TutorialTarget.appTitle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub_outlined, color: AppTheme.cyan, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'JudgeMatrixSE',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Restart tutorial',
                icon: const Icon(Icons.help_outline),
                onPressed:
                    () => TutorialController.instance.start(restart: true),
              ),
              IconButton(
                tooltip: 'Notifications',
                icon: Badge(
                  isLabelVisible: _unreadNotifications > 0,
                  label: Text('$_unreadNotifications'),
                  child: const Icon(Icons.notifications_none_outlined),
                ),
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => const NotificationsDialog(),
                  );
                  _loadNotificationCount();
                },
              ),
              // Current user chip
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: TutorialAnchor(
                  target: TutorialTarget.accountMenu,
                  child:
                      isPhone
                          ? IconButton(
                            tooltip: 'Profile',
                            onPressed: () => _go(5),
                            icon: UserAvatar(
                              name: auth.displayName,
                              avatar: '${auth.currentUser?['avatar'] ?? ''}',
                              radius: 14,
                            ),
                          )
                          : ActionChip(
                            backgroundColor: Colors.white.withValues(
                              alpha: .07,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: .10),
                            ),
                            avatar: UserAvatar(
                              name: auth.displayName,
                              avatar: '${auth.currentUser?['avatar'] ?? ''}',
                              radius: 11,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                auth.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            onPressed: () => _go(5),
                            tooltip: 'Logged in as ${auth.username}',
                          ),
                ),
              ),
              // Logout
              if (!isPhone)
                IconButton(
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout),
                  onPressed: () => _logout(context),
                ),
              SizedBox(width: isPhone ? 0 : 4),
            ],
          ),
          body:
              isPhone
                  ? page
                  : Row(
                    children: [
                      NavRail(idx: _idx, onSelect: _go),
                      Expanded(child: page),
                    ],
                  ),
        ),
        TutorialOverlay(onNavigate: _goFromTutorial),
      ],
    );
  }

  Widget _buildMobileDrawer(AuthService auth) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  UserAvatar(
                    name: auth.displayName,
                    avatar: '${auth.currentUser?['avatar'] ?? ''}',
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '@${auth.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final item in _mobileDestinations)
                    ListTile(
                      selected: _idx == item.index,
                      selectedColor: AppTheme.cyan,
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      onTap: () {
                        Navigator.pop(context);
                        _go(item.index);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () {
                Navigator.pop(context);
                _logout(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination(this.label, this.icon, this.index);

  final String label;
  final IconData icon;
  final int index;
}
