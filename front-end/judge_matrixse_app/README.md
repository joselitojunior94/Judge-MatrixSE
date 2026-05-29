# JudgeMatrixSE — Frontend

Flutter app for the JudgeMatrixSE tool: a collaborative human-judgment platform for structured datasets.

## Getting Started

```bash
flutter pub get
flutter run -d chrome
```

For a production web build:

```bash
flutter build web
```

Set your backend URL in `lib/service/api/api.dart` (`kApiBaseUrl`) before running.
