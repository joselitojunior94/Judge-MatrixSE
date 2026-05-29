import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tutorial_steps.dart';

class TutorialController extends ChangeNotifier {
  TutorialController._();

  static final TutorialController instance = TutorialController._();

  String? _username;
  int _step = 0;
  bool _active = false;
  bool _initialised = false;

  int get step => _step;
  bool get active => _active;
  bool get initialised => _initialised;
  TutorialStep get currentStep => tutorialSteps[_step];
  bool get isFirstStep => _step == 0;
  bool get isLastStep => _step == tutorialSteps.length - 1;

  String _completedKey(String username) => 'tutorial.completed.$username';
  String _skippedKey(String username) => 'tutorial.skipped.$username';

  Future<void> initForUser(String username) async {
    if (_initialised && _username == username) return;

    _username = username;
    _step = 0;
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_completedKey(username)) ?? false;
    final skipped = prefs.getBool(_skippedKey(username)) ?? false;
    _active = !completed && !skipped;
    _initialised = true;
    notifyListeners();
  }

  Future<void> start({bool restart = false}) async {
    final username = _username;
    if (username == null) return;

    if (restart) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_completedKey(username));
      await prefs.remove(_skippedKey(username));
    }

    _step = 0;
    _active = true;
    notifyListeners();
  }

  Future<void> skip() async {
    final username = _username;
    if (username != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_skippedKey(username), true);
    }
    _active = false;
    notifyListeners();
  }

  Future<void> finish() async {
    final username = _username;
    if (username != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey(username), true);
      await prefs.remove(_skippedKey(username));
    }
    _active = false;
    notifyListeners();
  }

  void next() {
    if (isLastStep) {
      finish();
      return;
    }
    _step += 1;
    notifyListeners();
  }

  void previous() {
    if (_step == 0) return;
    _step -= 1;
    notifyListeners();
  }
}
