// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class FeedbackFormFrame extends StatefulWidget {
  const FeedbackFormFrame({super.key, required this.url});

  final String url;

  @override
  State<FeedbackFormFrame> createState() => _FeedbackFormFrameState();
}

class _FeedbackFormFrameState extends State<FeedbackFormFrame> {
  late final String _viewType =
      'judgematrixse-feedback-form-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    final iframe =
        html.IFrameElement()
          ..src = widget.url
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;

    ui.platformViewRegistry.registerViewFactory(_viewType, (_) => iframe);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
