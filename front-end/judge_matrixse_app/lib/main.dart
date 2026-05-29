import 'package:flutter/material.dart';
import 'package:judge_matrixse_app/service/auth/auth_gate.dart';
import 'package:judge_matrixse_app/theme/app_theme.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JudgeMatrixSE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}
