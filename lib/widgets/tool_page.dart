import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A full-screen page for a tool that has no bottom-nav tab.
///
/// Task 8.1 (Phase 7 navigation decision): PCOS and Endometriosis lost
/// their tabs, so they are pushed as routes instead. Those screens are
/// written as tab content -- they draw their own branded header and
/// scroll body rather than a Scaffold -- so this wrapper supplies the
/// page Scaffold (background + a route the system back gesture can
/// pop). The screens add their own back arrow in the header when they
/// can pop.
class ToolPage extends StatelessWidget {
  final Widget child;

  const ToolPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppColors.background, body: child);
  }
}
