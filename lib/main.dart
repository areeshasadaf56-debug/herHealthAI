import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'l10n/language_fab.dart';
import 'l10n/language_provider.dart';
import 'screens/splash_screen.dart';
import 'services/health_profile_service.dart';
import 'theme/app_theme.dart';
import 'providers/cycle_provider.dart';

void main() {
  // All faces the UI renders are bundled under assets/fonts (Fredoka +
  // Nunito, see pubspec). Never reach out to fonts.gstatic.com at
  // runtime: offline first paint, and a missing variant falls back to
  // the platform font instead of hanging on a download (task 5.5).
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const WellnessSaheliApp());
}

class WellnessSaheliApp extends StatelessWidget {
  const WellnessSaheliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CycleProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // FR-79: a failed background profile push is retried on the next
    // save, load, AND app resume.
    if (state == AppLifecycleState.resumed) {
      HealthProfileService().retryPendingSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return MaterialApp(
      title: 'Wellness Saheli',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 'ur' makes Flutter lay everything out right-to-left automatically
      // and translates built-in widgets (date pickers, OK/Cancel, etc.).
      locale: lang.locale,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [child ?? const SizedBox.shrink(), const LanguageFab()],
      ),
      home: const SplashScreen(),
    );
  }
}
